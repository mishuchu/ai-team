# AI Team

> Multi-Agent Virtual Team Collaboration Framework

基于 Matrix 协议的多 Agent 虚拟人团队协作框架。在任意 PVE 主机上一键部署，通过自托管的 Matrix 服务器 + Element Web UI 实现人类管理员与 Agent 团队的无缝交互。

## 🎯 项目目标

- **完全自托管**：不依赖任何商业 IM 服务
- **一键部署**：Terraform + Ansible，任意 PVE 机器上自动化部署
- **账号自动化**：通过 API 一键创建 Agent 账号，无需手动操作
- **动态团队**：Agent 可随时加入/退出，支持角色动态分配
- **开源可扩展**：任何人都能基于此框架搭建自己的 AI 团队

## 🏗️ 架构

```
[外部用户] ──► [LXC 200: Gateway (nginx 反向代理)]
                      │  NAT + 端口映射
                      ├─► :80   → Element Web UI
                      ├─► :8448 → Dendrite Matrix API
                      │
                      ▼ 10.0.8.x 隔离子网
              ┌───────┴───────┬───────────────┐
              │               │               │
        [LXC 110]      [LXC 120]      [LXC 131-133...]
        Matrix         Element        Hermes Agent
        Dendrite       Web UI         × N (Team Leader,
        + PostgreSQL                    Architect, Core,
                                        Test Engineer)
```

**网络隔离：**
- `vmbr0` (物理网络): 192.168.111.x — PVE 原有网络
- `vmbr1` (隔离子网): 10.0.8.x — AI Team 内部网络
- LXC 200 (Gateway): 双网卡，同时连接两个网络，做 NAT + 反向代理

**服务发现：**
- 所有 AI Team 服务运行在 `10.0.8.x` 隔离子网内
- 外部用户通过 Gateway 的 80/8448 端口访问
- Agent 间通过 Matrix 协议通信

## 📦 模块

| 模块 | 路径 | 说明 |
|------|------|------|
| `infrastructure/terraform/` | IaC | Terraform: LXC 创建 + 网络配置 |
| `infrastructure/ansible/` | IaC | Ansible: 服务安装 + 配置 |
| `matrix/` | 消息服务 | Dendrite 配置 + Element Web 定制 |
| `agent/` | Agent 运行时 | Hermes Agent + matrix-nio SDK |
| `team/` | 团队管理 | Agent 角色定义 + 协作规则 |
| `docs/` | 文档 | 部署指南 + 使用手册 |

## 🚀 快速部署

```bash
# 1. 克隆仓库
git clone https://github.com/mishuchu/ai-team.git
cd ai-team

# 2. 配置 PVE 连接信息
cp infrastructure/terraform/ai-team.tfvars.example \
   infrastructure/terraform/ai-team.tfvars
# 编辑 ai-team.tfvars，填入你的 PVE IP 和密码

# 3. 一键部署（创建 LXC + 配置网络）
cd infrastructure/terraform
terraform init
terraform apply -var-file="ai-team.tfvars"

# 4. 等待 LXC 启动，然后配置服务
cd ../ansible
ansible-playbook -i inventory-ai-team.yml playbooks/ai-team-deploy.yml

# 5. 访问 Element Web
# 浏览器打开 http://<PVE-IP>/
```

## 📋 前提条件

- PVE 9.x 环境（任意 PVE 机器，物理机或虚拟机均可）
- Terraform >= 1.0
- Ansible >= 2.15
- PVE SSH key 认证（推荐）或密码认证
- PVE 上已有 `debian-12-standard` 模板在 `/var/lib/vz/template/cache/`

## 🧩 服务组件

| 组件 | LXC ID | IP | 端口 | 说明 |
|------|--------|-----|------|------|
| Gateway | 200 | 192.168.111.254 / 10.0.8.1 | 80, 8448 | NAT 路由器 + nginx 反向代理 |
| Matrix (Dendrite) | 110 | 10.0.8.10 | 8008 | Matrix homeserver |
| Element Web | 120 | 10.0.8.20 | 80 | Web UI |
| Agent Leader | 131 | 10.0.8.30 | — | Team Leader persona |
| Agent Architect | 132 | 10.0.8.31 | — | Architect persona |
| Agent Core | 133 | 10.0.8.32 | — | Core Engineer persona |
| Agent Tester | 134 | 10.0.8.33 | — | Test Engineer persona |

## 🛠️ 技术栈

- **Homeserver**: Dendrite (Go, 高性能低资源)
- **Web UI**: Element Web (TypeScript, 官方客户端)
- **Bot SDK**: matrix-nio (Python, 异步)
- **IaC**: Terraform + Ansible
- **Agent**: Hermes (Python)
- **网络**: LXC 双网卡 + NAT + nginx 反向代理

## 📄 License

MIT
