# Matrix Server Module
# Creates LXC container for Dendrite homeserver + PostgreSQL + Redis

variable "name" {
  type    = string
  default = "matrix-server"
}

variable "id" {
  type    = number
  default = 101
}

variable "memory" {
  type    = number
  default = 2048
}

variable "cpu" {
  type    = number
  default = 2
}

variable "disk_size" {
  type    = string
  default = "10G"
}

variable "ip" {
  type    = string
  default = "192.168.111.50"
}

variable "gateway" {
  type    = string
  default = "192.168.111.1"
}

variable "password" {
  type    = string
  sensitive = true
}

resource "proxmox_lxc" "matrix_server" {
  count      = 1
  id         = var.id
  name       = var.name
  node_name  = var.pve_node
  hostname   = var.name

  os_type    = "ubuntu"
  ostype     = "ubuntu"
  arch       = "amd64"

  memory     = var.memory
  cores      = var.cpu
  swap       = 0

  disk {
    size         = var.disk_size
    storage      = "local-lvm"
    type         = "root"
    cache        = "native"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "${var.ip}/24"
    gw     = var.gateway
    firewall = false
  }

  root_password = var.password

  on_boot   = true
  startup   = "order=1"

  provisioner "local-exec" {
    command = "echo 'Matrix server LXC ${var.id} created at ${var.ip}'"
  }
}

output "matrix_ip" {
  value = var.ip
}

output "matrix_hostname" {
  value = var.name
}