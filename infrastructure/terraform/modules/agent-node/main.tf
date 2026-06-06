# Agent Node Module
# Creates LXC container for Hermes Agent with matrix-nio

variable "name" {
  type = string
}

variable "id" {
  type = number
}

variable "memory" {
  type    = number
  default = 1024
}

variable "cpu" {
  type    = number
  default = 1
}

variable "disk_size" {
  type    = string
  default = "8G"
}

variable "ip" {
  type = string
}

variable "gateway" {
  type    = string
  default = "192.168.111.1"
}

variable "password" {
  type      = string
  sensitive = true
}

variable "matrix_server_ip" {
  type = string
}

variable "agent_name" {
  type = string
}

resource "proxmox_lxc" "agent_node" {
  count     = 1
  id        = var.id
  name      = var.name
  node_name = var.pve_node
  hostname  = var.name

  os_type  = "ubuntu"
  ostype   = "ubuntu"
  arch     = "amd64"

  memory   = var.memory
  cores    = var.cpu
  swap     = 0

  disk {
    size     = var.disk_size
    storage  = "local-lvm"
    type     = "root"
    cache    = "native"
  }

  network {
    name     = "eth0"
    bridge   = "vmbr0"
    ip       = "${var.ip}/24"
    gw       = var.gateway
    firewall = false
  }

  root_password = var.password

  on_boot = true
  startup = "order=2,up=30"

  provisioner "local-exec" {
    command = "echo 'Agent node ${var.name} (${var.id}) created at ${var.ip}'"
  }
}

output "agent_ip" {
  value = var.ip
}

output "agent_hostname" {
  value = var.name
}