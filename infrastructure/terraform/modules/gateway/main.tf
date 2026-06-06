# Gateway Module
# Creates LXC with dual NICs (or uses existing LXC 200) + nginx reverse proxy
#
# Provisioning via SSH (not telmate/proxmox LXC dual-NIC limitation):
#   1. Creates/updates LXC 200 with dual NICs via pct
#   2. Configures IP forwarding + NAT
#   3. Installs and configures nginx as reverse proxy

terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Determine if LXC 200 already exists
data "null_resource" "check_existing" {
  triggers = {
    vmid = var.vmid
  }
}

# ─── LXC Creation ────────────────────────────────────────────────────────────
resource "null_resource" "create_lxc" {
  triggers = {
    vmid           = var.vmid
    ip_physical    = var.ip_physical
    ip_internal    = var.ip_internal
    bridge_external = var.bridge_external
    bridge_internal = var.bridge_internal
    memory         = var.memory
    cpu            = var.cpu
    disk_size      = var.disk_size
    pve_node       = var.pve_node
  }

  # Create LXC via PVE SSH
  provisioner "remote-exec" {
    connection {
      host = var.ip_physical
      type     = "ssh"
      user     = "root"
      password = var.password
    }

    inline = [
      # Check if LXC exists
      "existing=$(pct list | grep -w '${var.vmid}' || echo '')",
      "[ -n \"$existing\" ] && echo \"LXC ${var.vmid} exists\" || {",
      # Create LXC if not exists
      "pct create ${var.vmid} /var/lib/vz/template/cache/debian-12-standard_amd64.tar.gz \\",
      "  --hostname ai-team-gateway \\",
      "  --memory ${var.memory} \\",
      "  --cores ${var.cpu} \\",
      "  --rootfs local-lvm:${var.disk_size} \\",
      "  --net0 name=eth0,bridge=${var.bridge_external},ip=${var.ip_physical}/24,gw=${var.gateway_physical} \\",
      "  --net1 name=eth1,bridge=${var.bridge_internal},ip=${var.ip_internal}/24 \\",
      "  --unprivileged 1 \\",
      "  --features keyctl=1 \\",
      "  --ostype debian \\",
      "  --onboot 1 \\",
      "  --startup order=1 \\",
      "  && echo \"LXC ${var.vmid} created\" || echo \"LXC ${var.vmid} already exists\"",
      "}"
    ]
  }
}

# ─── Configure: IP forwarding + NAT + nginx ─────────────────────────────────
resource "null_resource" "configure_gateway" {
  depends_on = [null_resource.create_lxc]

  triggers = {
    vmid           = var.vmid
    ip_physical    = var.ip_physical
    ip_internal    = var.ip_internal
    internal_subnet = var.internal_subnet
    matrix_ip      = var.matrix_ip
    element_ip    = var.element_ip
  }

  provisioner "remote-exec" {
    connection {
      host     = var.ip_internal
      type     = "ssh"
      user     = "root"
      password = var.password
    }

    inline = [
      # Enable IP forwarding
      "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",
      "sysctl -w net.ipv4.ip_forward=1",

      # NAT: MASQUERADE internal -> external
      "iptables -t nat -A POSTROUTING -s ${var.internal_subnet} ! -d ${var.internal_subnet} -j MASQUERADE",

      # Install nginx
      "apt-get update -qq && apt-get install -y -qq nginx",

      # nginx reverse proxy config
      "cat > /etc/nginx/sites-available/ai-team-proxy << 'NGINX_EOF'\n",
      "server {\n",
      "    listen 80;\n",
      "    server_name _;\n",
      "\n",
      "    location / {\n",
      "        proxy_pass http://${var.element_ip}:80;\n",
      "        proxy_set_header Host $host;\n",
      "        proxy_set_header X-Real-IP $remote_addr;\n",
      "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n",
      "    }\n",
      "\n",
      "    location /_matrix/ {\n",
      "        proxy_pass http://${var.matrix_ip}:8008/_matrix/;\n",
      "        proxy_set_header Host $host;\n",
      "        proxy_set_header X-Real-IP $remote_addr;\n",
      "    }\n",
      "\n",
      "    location /_synapse/ {\n",
      "        proxy_pass http://${var.matrix_ip}:8008/_synapse/;\n",
      "        proxy_set_header Host $host;\n",
      "    }\n",
      "}\nNGINX_EOF",

      # Enable site and reload nginx
      "ln -sf /etc/nginx/sites-available/ai-team-proxy /etc/nginx/sites-enabled/",
      "nginx -t && systemctl reload nginx",
    ]
  }
}

output "gateway_vmid" {
  value = var.vmid
}

output "gateway_ip_internal" {
  value = var.ip_internal
}

output "gateway_ip_physical" {
  value = var.ip_physical
}

output "matrix_proxy_port" {
  value = 8448
}

output "element_proxy_port" {
  value = 80
}