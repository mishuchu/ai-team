# Matrix Server Module
# LXC for Dendrite homeserver + PostgreSQL on isolated 10.0.8.x network

terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

variable "name" {
  type    = string
  default = "matrix-server"
}

variable "vmid" {
  type    = number
  default = 110
}

variable "memory" {
  type    = number
  default = 4096
}

variable "cpu" {
  type    = number
  default = 2
}

variable "disk_size" {
  type    = string
  default = "16G"
}

variable "ip" {
  type    = string
  default = "10.0.8.10"
}

variable "gateway" {
  type    = string
  default = "10.0.8.1"
}

variable "bridge" {
  type    = string
  default = "vmbr1"
}

variable "pve_node" {
  type    = string
  default = "pve"
}

variable "password" {
  type      = string
  sensitive = true
}

variable "matrix_domain" {
  type    = string
  default = "ai-team.local"
}

variable "registration_shared_secret" {
  type = string
  sensitive = true
}

resource "null_resource" "matrix_server" {
  triggers = {
    vmid   = var.vmid
    name = var.name
    ip     = var.ip
    bridge = var.bridge
  }

  provisioner "remote-exec" {
    connection {
      host     = var.gateway
      type     = "ssh"
      user     = "root"
      password = var.password
    }

    inline = [
      # Check if LXC exists
      "existing=$(pct list | grep -w '${var.vmid}' || echo '')",
      "[ -n \"$existing\" ] && echo \"LXC ${var.vmid} exists\" || {",
      "pct create ${var.vmid} /var/lib/vz/template/cache/debian-12-standard_amd64.tar.gz \\",
      "  --hostname ${var.name} \\",
      "  --memory ${var.memory} \\",
      "  --cores ${var.cpu} \\",
      "  --rootfs local-lvm:${var.disk_size} \\",
      "  --net0 name=eth0,bridge=${var.bridge},ip=${var.ip}/24,gw=${var.gateway} \\",
      "  --nameserver 8.8.8.8 \\",
      "  --unprivileged 1 \\",
      "  --features keyctl=1 \\",
      "  --ostype debian \\",
      "  --onboot 1 \\",
      "  --startup order=2,up=30 \\",
      "  && echo \"LXC ${var.vmid} created\"",
      "}",

      # Start LXC if stopped
      "pct start ${var.vmid}",
      "sleep 5",
    ]
  }
}

resource "null_resource" "install_dendrite" {
  depends_on = [null_resource.matrix_server]

  triggers = {
    vmid    = var.vmid
    ip      = var.ip
    gateway = var.gateway
    domain  = var.matrix_domain
    secret  = var.registration_shared_secret
  }

  provisioner "remote-exec" {
    connection {
      host     = var.gateway
      type     = "ssh"
      user     = "root"
      password = var.password
    }

    inline = [
      "pct exec ${var.vmid} -- bash -c \"",
      # Install prerequisites
      "apt-get update -qq && apt-get install -y -qq curl gnupg apt-transport-https lsb-release ca-certificates",

      # Install Go (Dendrite is Go)
      "curl -fsSL https://go.dev/dl/go1.22.linux-amd64.tar.gz | tar -C /usr/local -xzf -",

      # Clone and build Dendrite
      "git clone https://github.com/matrix-org/dendrite.git /opt/dendrite || echo 'dendrite already cloned'",
      "cd /opt/dendrite && go build -o bin/dendrite .",

      # Generate signing key
      "mkdir -p /etc/dendrite",
      "/opt/dendrite/bin/dendrite --generate-signing-key --database /opt/dendrite/dendrite.db --path /etc/dendrite/",

      # Write dendrite.yaml
      "cat > /etc/dendrite/dendrite.yaml << 'DEND_EOF'\n",
      "server_name: ${var.domain}\n",
      "database:\n",
      "  connection_string: file:///opt/dendrite/dendrite.db\n",
      "  max_open_conns: 10\n",
      " max_idle_conns: 5\n",
      "  conn_max_lifetime: -1\n",
      "listen:\n",
      "  address: 0.0.0.0\n",
      "  port: 8008\n",
      "  TLS: null\n",
      " bind_addresses:\n",
      "    - 0.0.0.0\n",
      "  database:\n",
      " connection_string: file:///opt/dendrite/dendrite.db\n",
      " registration_shared_secret: '${var.secret}'\n",
      "  macaroon_secret_key: '$(head -c 32 /dev/urandom | base64)'\n",
      "  private_key_path: /etc/dendrite/matrix_key.pem\n",
      "  public_key_path: /etc/dendrite/matrix_key.pem.pub\n",
      "DEND_EOF",

      # Create systemd service
      "cat > /etc/systemd/system/dendrite.service << 'DEND_SVC'\n",
      "[Unit]\n",
      "Description=Dendrite Matrix Homeserver\n",
      "After=network-online.target\n",
      "Wants=network-online.target\n",
      "\n",
      "[Service]\n",
      "ExecStart=/opt/dendrite/bin/dendrite --config /etc/dendrite/dendrite.yaml\n",
      "Restart=always\n",
      "RestartSec=5\n",
      "\n",
      "[Install]\n",
      "WantedBy=multi-user.target\n",
      "DEND_SVC",

      "systemctl daemon-reload",
      "systemctl enable dendrite",
      "systemctl start dendrite",
      "\""
    ]
  }
}

output "matrix_ip" {
  value = var.ip
}

output "matrix_vmid" {
  value = var.vmid
}

output "matrix_hostname" {
  value = var.name
}