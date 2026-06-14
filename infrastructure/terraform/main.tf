# AI Team - Main Terraform Configuration
# Deploys to PVE: gateway + matrix server + element web + agent nodes
# All services on isolated 10.0.8.x network, gateway (LXC 200) does NAT + reverse proxy

terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

variable "pve_host" {
  description = "PVE SSH host IP"
  type        = string
  default     = "192.168.111.4"
}

variable "pve_ssh_key" {
  description = "PVE SSH private key path"
  type        = string
  default     = "/opt/data/.ssh/pve_key"
}

variable "pve_node" {
  description = "PVE node name"
  type        = string
  default     = "pve"
}

variable "pve_password" {
  description = "Root password for containers"
  type        = string
  sensitive   = true
}

variable "internal_subnet" {
  description = "AI Team isolated subnet"
  type        = string
  default     = "10.0.8.0/24"
}

variable "gateway_vmid" {
  description = "VMID for gateway LXC (should be 200 for existing)"
  type        = number
  default     = 200
}

variable "gateway_ip_physical" {
  description = "Gateway IP on physical network side"
  type        = string
  default     = "192.168.111.254"
}

variable "gateway_ip_internal" {
  description = "Gateway IP on internal network side"
  type        = string
  default     = "10.0.8.1"
}

variable "gateway_physical_gateway" {
  description = "Gateway for physical network"
  type        = string
  default     = "192.168.111.1"
}

variable "bridge_external" {
  description = "Bridge for physical network"
  type        = string
  default     = "vmbr0"
}

variable "bridge_internal" {
  description = "Bridge for AI Team internal network"
  type        = string
  default     = "vmbr1"
}

variable "matrix_vmid" {
  type    = number
  default = 110
}

variable "matrix_ip" {
  type    = string
  default = "10.0.8.10"
}

variable "element_vmid" {
  type    = number
  default = 120
}

variable "element_ip" {
  type    = string
  default = "10.0.8.20"
}

variable "agent_count" {
  description = "Number of agent LXC containers"
  type        = number
  default     = 3
}

variable "agent_base_vmid" {
  type    = number
  default = 131
}

variable "agent_base_ip" {
  type    = string
  default = "10.0.8.30"
}

variable "agent_ip_prefix" {
  description = "IP prefix for agent nodes (e.g. 10.0.8)"
  type        = string
  default     = "10.0.8"
}

variable "matrix_domain" {
  type    = string
  default = "ai-team.local"
}

variable "matrix_registration_secret" {
  type      = string
  sensitive = true
}

# ─── Gateway LXC (LXC 200) ─────────────────────────────────────────────────
resource "null_resource" "gateway_lxc" {
  triggers = {
    vmid            = var.gateway_vmid
    ip_physical     = var.gateway_ip_physical
    ip_internal     = var.gateway_ip_internal
    bridge_external = var.bridge_external
    bridge_internal = var.bridge_internal
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i ${var.pve_ssh_key} -o StrictHostKeyChecking=no root@${var.pve_host} '
        existing=$(pct list 2>/dev/null | grep -w "${var.gateway_vmid}" || echo "")
        if [ -n "$existing" ]; then
          echo "Gateway LXC ${var.gateway_vmid} already exists"
        else
          echo "Creating gateway LXC ${var.gateway_vmid}..."
          pct create ${var.gateway_vmid} /var/lib/vz/template/cache/debian-12-standard_12.12-1_amd64.tar.zst \
            --hostname ai-team-gateway \
            --memory 512 \
            --cores 1 \
            --rootfs local-lvm:4G \
            --net0 name=eth0,bridge='${var.bridge_external}',ip='${var.gateway_ip_physical}'/24,gw='${var.gateway_physical_gateway}' \
            --net1 name=eth1,bridge='${var.bridge_internal}',ip='${var.gateway_ip_internal}'/24 \
            --nameserver 8.8.8.8 \
            --unprivileged 1 \
            --features keyctl=1 \
            --ostype debian \
            --onboot 1 \
            --startup order=1 \
            && echo "Gateway LXC ${var.gateway_vmid} created"
        fi
        pct start ${var.gateway_vmid}
        echo "Gateway LXC started"
      '
    EOT
  }
}

# ─── Matrix Server LXC ─────────────────────────────────────────────────────
resource "null_resource" "matrix_lxc" {
  triggers = {
    vmid   = var.matrix_vmid
    ip     = var.matrix_ip
    gateway = var.gateway_ip_internal
    bridge = var.bridge_internal
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i ${var.pve_ssh_key} -o StrictHostKeyChecking=no root@${var.pve_host} '
        existing=$(pct list 2>/dev/null | grep -w "${var.matrix_vmid}" || echo "")
        if [ -n "$existing" ]; then
          echo "Matrix LXC ${var.matrix_vmid} already exists"
        else
          echo "Creating matrix LXC ${var.matrix_vmid}..."
          pct create ${var.matrix_vmid} /var/lib/vz/template/cache/debian-12-standard_12.12-1_amd64.tar.zst \
            --hostname matrix-server \
            --memory 4096 \
            --cores 2 \
            --rootfs local-lvm:16G \
            --net0 name=eth0,bridge='${var.bridge_internal}',ip='${var.matrix_ip}'/24,gw='${var.gateway_ip_internal}' \
            --nameserver 8.8.8.8 \
            --unprivileged 1 \
            --features keyctl=1 \
            --ostype debian \
            --onboot 1 \
            --startup order=2,up=30 \
            && echo "Matrix LXC ${var.matrix_vmid} created"
        fi
        pct start ${var.matrix_vmid}
        echo "Matrix LXC started"
      '
    EOT
  }
}

# ─── Element Web LXC ──────────────────────────────────────────────────────
resource "null_resource" "element_lxc" {
  triggers = {
    vmid    = var.element_vmid
    ip      = var.element_ip
    gateway = var.gateway_ip_internal
    bridge  = var.bridge_internal
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i ${var.pve_ssh_key} -o StrictHostKeyChecking=no root@${var.pve_host} '
        existing=$(pct list 2>/dev/null | grep -w "${var.element_vmid}" || echo "")
        if [ -n "$existing" ]; then
          echo "Element LXC ${var.element_vmid} already exists"
        else
          echo "Creating element LXC ${var.element_vmid}..."
          pct create ${var.element_vmid} /var/lib/vz/template/cache/debian-12-standard_12.12-1_amd64.tar.zst \
            --hostname element-web \
            --memory 1024 \
            --cores 1 \
            --rootfs local-lvm:8G \
            --net0 name=eth0,bridge='${var.bridge_internal}',ip='${var.element_ip}'/24,gw='${var.gateway_ip_internal}' \
            --nameserver 8.8.8.8 \
            --unprivileged 1 \
            --features keyctl=1 \
            --ostype debian \
            --onboot 1 \
            --startup order=3,up=60 \
            && echo "Element LXC ${var.element_vmid} created"
        fi
        pct start ${var.element_vmid}
        echo "Element LXC started"
      '
    EOT
  }
}

# ─── Agent LXC Containers ──────────────────────────────────────────────────
resource "null_resource" "agent_containers" {
  count = var.agent_count

  triggers = {
    vmid_base = var.agent_base_vmid
    ip_base   = var.agent_base_ip
    gateway   = var.gateway_ip_internal
    bridge    = var.bridge_internal
    count     = var.agent_count
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i ${var.pve_ssh_key} -o StrictHostKeyChecking=no root@${var.pve_host} '
        vmid=${var.agent_base_vmid}
        ip_octet=$((vmid - ${var.agent_base_vmid} + 30))
        ip="${var.agent_ip_prefix}.$ip_octet"
        name="agent-node-$((vmid - ${var.agent_base_vmid}))"
        echo "Creating agent LXC $name (VMID $vmid, IP $ip)..."
        existing=$(pct list 2>/dev/null | grep -w "$vmid" || echo "")
        if [ -n "$existing" ]; then
          echo "Agent LXC $vmid already exists"
        else
          pct create $vmid /var/lib/vz/template/cache/debian-12-standard_12.12-1_amd64.tar.zst \
            --hostname "$name" \
            --memory 2048 \
            --cores 1 \
            --rootfs local-lvm:8G \
            --net0 name=eth0,bridge='${var.bridge_internal}',ip="$ip/24",gw='${var.gateway_ip_internal}' \
            --nameserver 8.8.8.8 \
            --unprivileged 1 \
            --features keyctl=1 \
            --ostype debian \
            --onboot 1 \
            --startup order=$((4 + ${count.index})),up=90 \
            && echo "Agent LXC $vmid created"
        fi
        pct start $vmid
        echo "Agent LXC $vmid started"
      '
    EOT
  }
}

# ─── Outputs ────────────────────────────────────────────────────────────────
output "gateway" {
  description = "Gateway LXC info"
  value = {
    vmid         = var.gateway_vmid
    ip_physical  = var.gateway_ip_physical
    ip_internal  = var.gateway_ip_internal
  }
}

output "matrix_server" {
  description = "Matrix server info"
  value = {
    vmid = var.matrix_vmid
    ip   = var.matrix_ip
  }
}

output "element_web" {
  description = "Element Web info"
  value = {
    vmid = var.element_vmid
    ip   = var.element_ip
  }
}

output "agent_nodes" {
  description = "Agent node IPs"
  value = [for i in range(var.agent_count) : "${var.agent_ip_prefix}.$((30 + i))"]
}