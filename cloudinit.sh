#!/bin/bash

# Local_model_A10.2_${MODEL}

echo "running cloudinit.sh script"
dnf install -y dnf-utils zip unzip gcc
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf remove -y runc

echo "INSTALL DOCKER"
dnf install -y docker-ce --nobest

echo "ENABLE DOCKER"
systemctl enable docker.service

echo "INSTALL NVIDIA CONT TOOLKIT"
dnf install -y nvidia-container-toolkit

echo "START DOCKER"
systemctl start docker.service

echo "PYTHON packages"
python3 -m pip install --upgrade pip wheel oci
python3 -m pip install --upgrade setuptools
python3 -m pip install oci-cli
python3 -m pip install langchain
python3 -m pip install python-multipart
python3 -m pip install pypdf
python3 -m pip install six

echo "GROWFS"
/usr/libexec/oci-growfs -y

echo "BASHRC"
sudo -u opc echo "export MODEL='${MODEL}'" >> /home/opc/.bashrc

echo "Export nvcc"
sudo -u opc bash -c 'echo "export PATH=\$PATH:/usr/local/cuda/bin" >> /home/opc/.bashrc'

echo "Add docker opc"
sudo usermod -aG docker

echo "Python 3.10.6"
dnf install curl gcc openssl-devel bzip2-devel libffi-devel zlib-devel wget make -y
wget https://www.python.org/ftp/python/3.10.6/Python-3.10.6.tar.xz
tar -xf Python-3.10.6.tar.xz
cd Python-3.10.6/
./configure --enable-optimizations
make -j $(nproc)
sudo make altinstall
python3.10 -V
cd ..
rm -rf Python-3.10.6*

echo "Git"
dnf install -y git

echo "Conda"
mkdir -p /home/opc/miniconda3
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /home/opc/miniconda3/miniconda.sh
bash /home/opc/miniconda3/miniconda.sh -b -u -p /home/opc/miniconda3
rm -rf /home/opc/miniconda3/miniconda.sh
/home/opc/miniconda3/bin/conda init bash
chown -R opc:opc /home/opc/miniconda3
su - opc -c "/home/opc/miniconda3/bin/conda init bash"

# Ensure the .bashrc is reloaded
sudo -u opc bash -c "source /home/opc/.bashrc"

echo "Conda env"
su - opc -c "/home/opc/miniconda3/bin/conda create -n elyza python=3.10.9 -y"
echo "source activate elyza" >> /home/opc/.bashrc
su - opc -c "source /home/opc/.bashrc && \
             conda activate elyza && \
             conda install pip -y && \
             pip install torch torchvision torchaudio -f https://download.pytorch.org/whl/cu118 && \
             pip install jupyter vllm"

# Create the directory if it does not exist
LOCAL_DIR="/home/opc/models/${MODEL}"
mkdir -p $LOCAL_DIR
sudo chown -R opc:opc $LOCAL_DIR
sudo chmod -R 755 /home/opc/models/
sudo chown -R opc:opc /home/opc/models

echo "Download Hugging Face $MODEL"
echo "Prepare libraries"
# Prepare libraries
su - opc -c "source /home/opc/.bashrc && \
             conda activate elyza && \
             pip install huggingface-hub tqdm"
# Download the model
date
echo "Starting $MODEL download"

su - opc -c 'export MODEL_NAME="elyza/${MODEL}"; \
             export LOCAL_DIR="/home/opc/models/${MODEL}"; \
             /home/opc/miniconda3/envs/elyza/bin/python3 - <<EOF
import os
from huggingface_hub import snapshot_download
from tqdm import tqdm

model_name = os.getenv("MODEL_NAME")
local_dir = os.getenv("LOCAL_DIR")

os.makedirs(local_dir, exist_ok=True)

snapshot_download(repo_id=model_name, local_dir=local_dir, force_download=True, tqdm_class=tqdm)

print(f"Downloaded model {model_name} to {local_dir}")
EOF'

echo "Installation complete"
date


echo "Starting model server as opc and elyza env"
su - opc -c "source /home/opc/.bashrc && \
             conda activate elyza && \
             nohup python -O -u -m vllm.entrypoints.api_server \
                 --host 0.0.0.0 \
                 --port 8000 \
                 --model /home/opc/models/${MODEL} \
                 --tokenizer hf-internal-testing/llama-tokenizer \
                 --enforce-eager \
                 --max-num-seqs 1 \
                 --tensor-parallel-size 2 \
                 >> /home/opc/${MODEL}.log 2>&1 &"

echo "Model server started and logging to /home/opc/${MODEL}.log"

echo "Starting Jupyter Notebook server as opc and elyza env..."
su - opc -c "source /home/opc/.bashrc && \
             conda activate elyza && \
             nohup jupyter notebook --ip=0.0.0.0 --port=8888 > /home/opc/jupyter.log 2>&1 &"
date

echo "Adding notebook details"

su - opc -c 'source /home/opc/.bashrc && \
             conda activate elyza && \
             pip install gradio && \
             cat <<EOF > /home/opc/query_model.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 5,
   "id": "1026a125",
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "Response: {\n",
      "    \"text\": [\n",
      "        \"Write a short conclusion.\\n\\u305f\\u3060\\u3057\\u3001\\u500b\\u4eba\\u7684\\u306a\\u611f\\u60c5\\u3084\\u4e3b\\u89b3\\u7684\\u306a\\u610f\\u898b\\u3092\\u542b\\u3080\\u60c5\\u5831\\u306f\\u3001\\u533b\\u5e2b\\u306e\\u5224\\u65ad\\u3092\\u8aa4\\u3089\\u305b\\u308b\\u53ef\\u80fd\\u6027\\u304c\\u3042\\u308b\\u305f\\u3081\\u3001\\u60a3\\u8005\\u3055\\u3093\\u306b\\u3088\"\n",
      "    ]\n",
      "}\n"
     ]
    }
   ],
   "source": [
    "import requests\n",
    "import json\n",
    "\n",
    "url = \"http://0.0.0.0:8000/generate\"\n",
    "headers = {\n",
    "    \"accept\": \"application/json\",\n",
    "    \"Content-Type\": \"application/json\",\n",
    "}\n",
    "\n",
    "data = {\n",
    "    \"prompt\": \"Write a short conclusion.\",\n",
    "    \"max_tokens\": 64,\n",
    "    \"temperature\": 0.7,\n",
    "    \"top_p\": 0.9\n",
    "}\n",
    "\n",
    "response = requests.post(url, headers=headers, json=data)\n",
    "\n",
    "if response.status_code == 200:\n",
    "    result = response.json()\n",
    "    # Pretty print the response for better readability\n",
    "    formatted_response = json.dumps(result, indent=4)\n",
    "    print(\"Response:\", formatted_response)\n",
    "else:\n",
    "    print(\"Request failed with status code:\", response.status_code)\n",
    "    print(\"Response:\", response.text)\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "id": "0eaea4cf-73db-479f-9ae3-f8fd381c5bc5",
   "metadata": {},
   "outputs": [],
   "source": []
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3 (ipykernel)",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.10.14"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
EOF

cat <<EOF > /home/opc/query_model_chat_gradio.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "id": "4dcba269-63c8-426d-bbb5-e0b541fac752",
   "metadata": {},
   "outputs": [],
   "source": [
    "import requests\n",
    "import gradio as gr\n",
    "import os\n",
    "\n",
    "# Function to interact with the model via API\n",
    "def interact_with_model(prompt):\n",
    "    url = 'http://0.0.0.0:8000/generate'\n",
    "    headers = {\n",
    "        \"accept\": \"application/json\",\n",
    "        \"Content-Type\": \"application/json\",\n",
    "    }\n",
    "\n",
    "    data = {\n",
    "        \"prompt\": prompt,\n",
    "        \"max_tokens\": 64,\n",
    "        \"temperature\": 0.7,\n",
    "        \"top_p\": 0.9\n",
    "    }\n",
    "\n",
    "    response = requests.post(url, headers=headers, json=data)\n",
    "\n",
    "    if response.status_code == 200:\n",
    "        result = response.json()\n",
    "        completion_text = result[\"text\"][0].strip()  # Extract the generated text\n",
    "        return completion_text\n",
    "    else:\n",
    "        return {\"error\": f\"Request failed with status code {response.status_code}\"}\n",
    "\n",
    "# Retrieve the MODEL environment variable\n",
    "model_name = os.getenv(\"MODEL\")\n",
    "\n",
    "# Example Gradio interface\n",
    "iface = gr.Interface(\n",
    "    fn=interact_with_model,\n",
    "    inputs=gr.Textbox(lines=2, placeholder=\"Write a prompt...\"),\n",
    "    outputs=gr.Textbox(type=\"text\", placeholder=\"Response...\"),\n",
    "    title=f\"{model_name} Interface\",  # Use model_name to dynamically set the title\n",
    "    description=f\"Interact with the {model_name} deployed locally via Gradio.\",  # Use model_name to dynamically set the description\n",
    "    live=True\n",
    ")\n",
    "\n",
    "# Launch the Gradio interface\n",
    "iface.launch(share=True)\n"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3 (ipykernel)",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.10.14"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
EOF'

# # Download and install OCI CLI
# echo "Install OCI CLI"
# curl -L -o /home/opc/install.sh https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh
# sudo chown opc:opc /home/opc/install.sh
# chmod a+x /home/opc/install.sh
# sudo -u opc /home/opc/install.sh --accept-all-defaults
# sudo -u opc mkdir -p /home/opc/.oci

# echo "Firewall commands to allow Jupyter access"
# su - opc -c "conda activate elyza && \
#              sudo firewall-cmd --zone=public --permanent --add-port 8888/tcp && \
#              sudo firewall-cmd --reload"

