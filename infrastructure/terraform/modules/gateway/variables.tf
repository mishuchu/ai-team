# Gateway Module
# LXC 200: NAT router + nginx reverse proxy for AI Team services
#
# Network topology:
#   eth0: 192.168.111.254/24 (physical network side)
#   eth1: 10.0.8.1/24 (AI Team isolated network side)
#
# Ports exposed to physical network:
#   80  -> Element Web HTTP
#   443 -> Element Web HTTPS
#   8448 -> Dendrite Matrix API
#   9090 -> Admin dashboard

variable "vmid" {
  type    = number
  default = 200
}

variable "memory" {
  type    = number
  default = 512
}

variable "cpu" {
  type    = number
  default = 1
}

variable "disk_size" {
  type    = string
  default = "4G"
}

variable "ip_physical" {
  type    = string
  default = "192.168.111.254"
}

variable "ip_internal" {
  type    = string
  default = "10.0.8.1"
}

variable "gateway_physical" {
  type    = string
  default = "192.168.111.1"
}

variable "pve_node" {
  type    = string
  default = "pve"
}

variable "bridge_external" {
  description = "Bridge for physical network side"
  type        = string
  default     = "vmbr0"
}

variable "bridge_internal" {
  description = "Bridge for AI Team isolated network"
  type        = string
  default     = "vmbr1"
}

variable "internal_subnet" {
  type    = string
  default = "10.0.8.0/24"
}

variable "matrix_ip" {
  type    = string
  default = "10.0.8.10"
}

variable "element_ip" {
  type    = string
  default = "10.0.8.20"
}

variable "password" {
  type      = string
  sensitive = true
}