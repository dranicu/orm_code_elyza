# Deploying ORM Stack for A10.2 GPU with local vLLM Elyza
In this guide, we'll walk through the steps required to deploy an Oracle Cloud Infrastructure (OCI) Resource Manager (ORM) stack that provisions an A10 shape instance with two GPUs. The setup also includes configuring the instance to run a local vLLM Elyza model(s) for natural language processing tasks.

## Installation
To begin, you can utilize OCI's Resource Manager from the console to upload and execute the deployment code. Ensure you have access to an OCI Virtual Cloud Network (VCN) and a subnet where the VM will be deployed.

## Requirements
- **Instance Type**: A10.2 shape with two GPUs.
- **Operating System**: Oracle Linux.
- **Image Selection**: The deployment script selects the latest Oracle Linux image with GPU support.
- 
  ```
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "launch_mode"
    values = ["NATIVE"]
  }
  filter {
    name = "display_name"
    values = ["\\w*GPU\\w*"]
    regex = true
  }
  ```
- **Tags: Adds a freeform tag GPU_TAG = "A10-2"**
- **Boot Volume Size: 250 GB.**
- **Initialization: Uses cloud-init to download and configure the vLLM Elyza model(s).**
## Cloud-init Configuration 
The cloud-init script installs necessary dependencies, starts Docker and downloads and starts the vLLM Mistral model(s).
```
dnf install -y dnf-utils zip unzip
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf remove -y runc
dnf install -y docker-ce --nobest
systemctl enable docker.service
dnf install -y nvidia-container-toolkit
systemctl start docker.service
...
```
## Monitoring the system
Track cloud-init completion and  GPU resource usage with these commands (if needed):
- **Monitor cloud-init completion:** tail -f /var/log/cloud-init-output.log
- **Monitor GPUs utilization:** nvidia-smi dmon -s mu -c 100 --id 0,1
## Starting the vLLM model
- **Deploy and interact with the vLLM Elyza model using Python.**
- *Adjust the parameters only if needed.:*
```
python -O -u -m vllm.entrypoints.api_server \
                 --host 0.0.0.0 \
                 --port 8000 \
                 --model /home/opc/models/${MODEL} \
                 --tokenizer hf-internal-testing/llama-tokenizer \
                 --enforce-eager \
                 --max-num-seqs 1 \
                 --tensor-parallel-size 2 \
                 >> /home/opc/${MODEL}.log 2>&1
```
## Testing the model integration
- **Test the model from CLI once cloud-init has completed:**
```
curl -X POST "http://0.0.0.0:8000/generate" \
     -H "accept: application/json" \
     -H "Content-Type: application/json" \
     -d '{"prompt": "Write a humorous limerick about the wonders of GPU computing.", "max_tokens": 64, "temperature": 0.7, "top_p": 0.9}'
```
- **Test the model from Jupyter notebook (Please open port 8888):**
```
import requests
import json

url = "http://0.0.0.0:8000/generate"
headers = {
    "accept": "application/json",
    "Content-Type": "application/json",
}

data = {
    "prompt": "Write a short conclusion.",
    "max_tokens": 64,
    "temperature": 0.7,
    "top_p": 0.9
}

response = requests.post(url, headers=headers, json=data)

if response.status_code == 200:
    result = response.json()
    # Pretty print the response for better readability
    formatted_response = json.dumps(result, indent=4)
    print("Response:", formatted_response)
else:
    print("Request failed with status code:", response.status_code)
    print("Response:", response.text)
```
- **Gradio integration with chatbot feaure to query the model:**
```
import requests
import gradio as gr
import os

# Function to interact with the model via API
def interact_with_model(prompt):
    url = 'http://0.0.0.0:8000/generate'
    headers = {
        "accept": "application/json",
        "Content-Type": "application/json",
    }

    data = {
        "prompt": prompt,
        "max_tokens": 64,
        "temperature": 0.7,
        "top_p": 0.9
    }

    response = requests.post(url, headers=headers, json=data)

    if response.status_code == 200:
        result = response.json()
        completion_text = result["text"][0].strip()  # Extract the generated text
        return completion_text
    else:
        return {"error": f"Request failed with status code {response.status_code}"}

# Retrieve the MODEL environment variable
model_name = os.getenv("MODEL")

# Example Gradio interface
iface = gr.Interface(
    fn=interact_with_model,
    inputs=gr.Textbox(lines=2, placeholder="Write a prompt..."),
    outputs=gr.Textbox(type="text", placeholder="Response..."),
    title=f"{model_name} Interface",  # Use model_name to dynamically set the title
    description=f"Interact with the {model_name} deployed locally via Gradio.",  # Use model_name to dynamically set the description
    live=True
)

# Launch the Gradio interface
iface.launch(share=True)
```
- **Docker deployment:**
- *Alternatively, deploy the model using Docker from external source:*
```
docker run --gpus all \
     --env "HUGGING_FACE_HUB_TOKEN=$TOKEN_ACCESS" \
     -p 8000:8000 \
     --ipc=host \
     --restart always \
     vllm/vllm-openai:latest \
     --tensor-parallel-size 2 \
     --model elyza/$MODEL 
```
- *To run docker from local files collected for the model (this version starts quicker compared to external source):*
```
docker run --gpus all \
-v /home/opc/models/$MODEL/:/mnt/model/ \
--env "HUGGING_FACE_HUB_TOKEN=$TOKEN_ACCESS" \
-p 8000:8000 \
--env "TRANSFORMERS_OFFLINE=1" \
--env "HF_DATASET_OFFLINE=1" \
--ipc=host vllm/vllm-openai:latest \
--model="/mnt/model/" \
--tensor-parallel-size 2

```
- **Query the model launched with Docker from CLI (this needs further attention):**
- *Container started from Docker external source:*
```
(elyza) [opc@a10-2-gpu ~]$ curl -X 'POST' 'http://0.0.0.0:8000/v1/chat/completions' \
-H 'accept: application/json' \
-H 'Content-Type: application/json' \
-d '{
    "model": "elyza/'${MODEL}'",
    "messages": [{"role": "user", "content": "Write a humorous limerick about the wonders of GPU computing."}],
     "max_tokens": 64,
    "temperature": 0.7,
     "top_p": 0.9
 }'
```
- *Container started locally from model files with Docker:*
```
curl -X 'POST' 'http://0.0.0.0:8000/v1/chat/completions' -H 'accept: application/json' -H 'Content-Type: application/json' -d '{
    "model": "/mnt/model/",
    "messages": [{"role": "user", "content": "Write a humorous limerick about the wonders of GPU computing."}],
     "max_tokens": 64,
    "temperature": 0.7,
     "top_p": 0.9
 }'
```
- **Query the model started with Docker from a Jupyter notebook:**
- *Container started from Docker Hub:*
```
import requests
import json
import os

url = "http://0.0.0.0:8000/v1/chat/completions"
headers = {
    "accept": "application/json",
    "Content-Type": "application/json",
}

# Assuming `MODEL` is an environment variable set appropriately
model = f"elyza/{os.getenv('MODEL')}"

data = {
    "model": model,
    "messages": [{"role": "user", "content": "Write a humorous limerick about the wonders of GPU computing."}],
    "max_tokens": 64,
    "temperature": 0.7,
    "top_p": 0.9
}

response = requests.post(url, headers=headers, json=data)

if response.status_code == 200:
    result = response.json()
    # Extract the generated text from the response
    completion_text = result["choices"][0]["message"]["content"].strip()
    print("Generated Text:", completion_text)
else:
    print("Request failed with status code:", response.status_code)
    print("Response:", response.text)
```
- *Container started locally with Docker:*
```
import requests
import json
import os

url = "http://0.0.0.0:8000/v1/chat/completions"
headers = {
    "accept": "application/json",
    "Content-Type": "application/json",
}

# Assuming `MODEL` is an environment variable set appropriately
model = f"/mnt/model/"  # Adjust this based on your specific model path or name

data = {
    "model": model,
    "messages": [{"role": "user", "content": "Write a humorous limerick about the wonders of GPU computing."}],
    "max_tokens": 64,
    "temperature": 0.7,
    "top_p": 0.9
}

response = requests.post(url, headers=headers, json=data)

if response.status_code == 200:
    result = response.json()
    # Extract the generated text from the response
    completion_text = result["choices"][0]["message"]["content"].strip()
    print("Generated Text:", completion_text)
else:
    print("Request failed with status code:", response.status_code)
    print("Response:", response.text)
```
- **Gradio integration with chatbot feature to query the model started with Docker:**
- *Container started from Docker Hub:*
```
import requests
import gradio as gr
import os

# Function to interact with the model via API
def interact_with_model(prompt):
    url = 'http://0.0.0.0:8000/v1/chat/completions'  # Update the URL to match the correct endpoint
    headers = {
        "accept": "application/json",
        "Content-Type": "application/json",
    }

    # Assuming `MODEL` is an environment variable set appropriately
    model = f"elyza/{os.getenv('MODEL')}"

    data = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],  # Use the user-provided prompt
        "max_tokens": 64,
        "temperature": 0.7,
        "top_p": 0.9
    }

    response = requests.post(url, headers=headers, json=data)

    if response.status_code == 200:
        result = response.json()
        completion_text = result["choices"][0]["message"]["content"].strip()  # Extract the generated text
        return completion_text
    else:
        return {"error": f"Request failed with status code {response.status_code}"}

# Retrieve the MODEL environment variable
model_name = os.getenv("MODEL")

# Example Gradio interface
iface = gr.Interface(
    fn=interact_with_model,
    inputs=gr.Textbox(lines=2, placeholder="Write a prompt..."),
    outputs=gr.Textbox(type="text", placeholder="Response..."),
    title=f"{model_name} Interface",  # Use model_name to dynamically set the title
    description=f"Interact with the {model_name} model deployed locally via Gradio.",  # Use model_name to dynamically set the description
    live=True
)

# Launch the Gradio interface
iface.launch(share=True)
```
- *Container started locally with Docker and using Gradio:*
```
import requests
import gradio as gr
import os

# Function to interact with the model via API
def interact_with_model(prompt):
    url = 'http://0.0.0.0:8000/v1/chat/completions'  # Update the URL to match the correct endpoint
    headers = {
        "accept": "application/json",
        "Content-Type": "application/json",
    }

    # Assuming `MODEL` is an environment variable set appropriately
    model = "/mnt/model/"  # Adjust this based on your specific model path or name

    data = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 64,
        "temperature": 0.7,
        "top_p": 0.9
    }

    response = requests.post(url, headers=headers, json=data)

    if response.status_code == 200:
        result = response.json()
        completion_text = result["choices"][0]["message"]["content"].strip()
        return completion_text
    else:
        return {"error": f"Request failed with status code {response.status_code}"}

# Example Gradio interface
iface = gr.Interface(
    fn=interact_with_model,
    inputs=gr.Textbox(lines=2, placeholder="Write a humorous limerick about the wonders of GPU computing."),
    outputs=gr.Textbox(type="text", placeholder="Response..."),
    title="Model Interface",  # Set your desired title here
    description="Interact with the model deployed locally via Gradio.",
    live=True
)

# Launch the Gradio interface
iface.launch(share=True)
```

**Firewall commands to open port 8888 for Jupyter:**
```
sudo firewall-cmd --zone=public --permanent --add-port 8888/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```