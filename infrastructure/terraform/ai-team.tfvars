# AI Team - Terraform Variables
# Deploy to a fresh PVE host

pve_host             = "192.168.111.4"
pve_ssh_key          = "/opt/data/.ssh/pve_key"
pve_node             = "pve"
pve_password         = "changeme"

# Network: isolated 10.0.8.x for AI Team services
internal_subnet      = "10.0.8.0/24"

# Gateway (LXC 200): NAT router + nginx reverse proxy
gateway_vmid         = 200
gateway_ip_physical  = "192.168.111.254"   # on vmbr0 (physical network)
gateway_ip_internal  = "10.0.8.1"           # on vmbr1 (isolated network)
gateway_physical_gateway = "192.168.111.1"   # upstream gateway for physical side
bridge_external      = "vmbr0"
bridge_internal      = "vmbr1"

# Matrix Dendrite (LXC 110)
matrix_vmid          = 110
matrix_ip            = "10.0.8.10"
matrix_domain        = "ai-team.local"

# Element Web UI (LXC 120)
element_vmid         = 120
element_ip           = "10.0.8.20"

# Agent nodes (LXC 131, 132, 133...)
agent_count          = 4
agent_base_vmid     = 131
agent_base_ip       = "10.0.8.30"
