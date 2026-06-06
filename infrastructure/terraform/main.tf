# AI Team - Infrastructure Module
# Terraform configuration for PVE-based deployment

terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 3.0"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.pve_api_url
  pm_api_token_id     = var.pve_token_id
  pm_api_token_secret = var.pve_token_secret
  pm_tls_insecure     = true
}

variable "pve_api_url" {
  description = "PVE API URL"
  type        = string
  default     = "https://192.168.111.4:8006/api2/json"
}

variable "pve_token_id" {
  description = "PVE API Token ID"
  type        = string
  sensitive   = true
}

variable "pve_token_secret" {
  description = "PVE API Token Secret"
  type        = string
  sensitive   = true
}

variable "pve_node" {
  description = "PVE node name"
  type        = string
  default     = "pve"
}

variable "vm_password" {
  description = "Root password for VMs"
  type        = string
  sensitive   = true
}

variable "matrix_server_ip" {
  description = "Matrix homeserver IP"
  type        = string
  default     = "192.168.111.50"
}

variable "agent_base_ip" {
  description = "Base IP for agent containers"
  type        = string
  default     = "192.168.111.60"
}

variable "agent_count" {
  description = "Number of agent containers to create"
  type        = number
  default     = 3
}

variable "bridge_ip" {
  description = "PVE bridge IP (vmbr0 gateway)"
  type        = string
  default     = "192.168.111.1"
}

variable "subnet_cidr" {
  description = "Subnet CIDR for containers"
  type        = string
  default     = "192.168.111.0/24"
}

output "matrix_server_ip" {
  value = var.matrix_server_ip
}

output "agent_ips" {
  value = [for i in range(var.agent_count) : cidrhost(var.subnet_cidr, 60 + i)]
}