## Copyright (c) 2023, Oracle and/or its affiliates.
## All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.10.0"
    }
  }
  required_version = "= 1.2.9"
}

variable "compartment_ocid" {}


# 
variable vcn_id {
  type = string
}

variable  subnet_id {
  type = string
 }


 variable vm_display_name {
  type = string
  default = "A10.2-GPU"
}

variable ssh_public_key {
  type = string
  default = ""
}

variable ad {
  type = string
  default = ""
}

variable "model" {
  type        = string
  description = "Choose the model type"
  default = "ELYZA-japanese-Llama-2-7b || ELYZA-japanese-Llama-2-7b-instruct || ELYZA-japanese-Llama-2-7b-fast || ELYZA-japanese-Llama-2-7b-fast-instruct"
  validation {
    condition     = var.model == "ELYZA-japanese-Llama-2-7b" || var.model == "ELYZA-japanese-Llama-2-7b-instruct" || var.model == "ELYZA-japanese-Llama-2-7b-fast" || var.model == "ELYZA-japanese-Llama-2-7b-fast-instruct"
    error_message = "Invalid model type. Allowed values are 'ELYZA-japanese-Llama-2-7b' or 'ELYZA-japanese-Llama-2-7b-instruct' or 'ELYZA-japanese-Llama-2-7b-fast' or 'ELYZA-japanese-Llama-2-7b-fast-instruct'."
  }
}
