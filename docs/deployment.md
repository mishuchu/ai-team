# 部署指南

## 环境要求

- PVE 9.x
- Terraform >= 1.6
- Ansible >= 2.15
- 至少 8GB RAM 可用

## 快速部署

### 1. 克隆仓库

```bash
git clone https://github.com/mishuchu/ai-team.git
cd ai-team
```

### 2. 配置 PVE 访问

创建 `infrastructure/terraform/terraform.tfvars`:

```hcl
pve_api_url     = "https://<PVE-IP>:8006/api2/json"
pve_token_id    = "terraform@pam!terraform"
pve_token_secret = "<YOUR-TOKEN-SECRET>"
pve_node        = "pve"
vm_password     = "<ROOT-PASSWORD>"
matrix_domain   = "matrix.ai-team.local"
```

### 3. 生成 PVE API Token

在 PVE Web UI:
1. Datacenter → API Tokens → Add
2. Token ID: `terraform@pam!terraform`
3. 复制生成的 Secret

### 4. 部署基础设施

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

### 5. 配置 Ansible

创建 `infrastructure/ansible/inventory/hosts.yml`:

```yaml
all:
  hosts:
    matrix-server:
      ansible_host: 192.168.111.50
      ansible_user: root
      ansible_password: "<ROOT-PASSWORD>"
      matrix_domain: matrix.ai-team.local
      db_user: dendrite
      db_password: "<DB-PASSWORD>"
      registration_shared_secret: "<GENERATED-SECRET>"
```

### 6. 运行 Ansible Playbooks

```bash
cd infrastructure/ansible

# 部署 Matrix 服务器
ansible-playbook -i inventory/hosts.yml playbook-matrix.yml

# 部署 Agent 节点
ansible-playbook -i inventory/hosts.yml playbook-agents.yml
```

## 创建 Agent 账号

```bash
cd matrix/scripts

# 创建 admin 账号
SHARED_SECRET="<registration_shared_secret>" \
  ./create-account.sh admin <password>

# 创建 worker 账号
SHARED_SECRET="<registration_shared_secret>" \
  ./create-account.sh worker1 <password>
```

## 访问

- **Element Web**: `http://192.168.111.50` (或配置域名 `https://element.ai-team.local`)
- **Matrix Server**: `http://192.168.111.50:8008`

## 故障排除

### Dendrite 无法启动

```bash
journalctl -u dendrite -f
cat /etc/dendrite/dendrite.yaml
```

### Agent 无法连接

```bash
# 检查 Matrix 服务器状态
curl http://localhost:8008/_matrix/client/versions

# 检查 Agent 日志
journalctl -u hermes-agent@<name> -f
```