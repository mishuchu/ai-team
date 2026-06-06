# AI Team

> Multi-Agent Virtual Team Collaboration Framework

基于 Matrix 协议的多 Agent 虚拟人团队协作框架。通过自托管的 Matrix 服务器 + Element Web UI，实现人类管理员与 Agent 团队的无缝交互。

## 🎯 项目目标

- **完全自托管**：不依赖任何商业 IM 服务
- **账号自动化**：通过 API 一键创建 Agent 账号，无需手动操作
- **动态团队**：Agent 可随时加入/退出，支持角色动态分配
- **开源可扩展**：任何人都能基于此框架搭建自己的 AI 团队

## 🏗️ 架构

```
┌─────────────────────────────────────────────────────────┐
│  人类管理员 (Element Web / 移动端)                        │
└─────────────────────┬───────────────────────────────────┘
                      │ HTTPS
┌─────────────────────┴───────────────────────────────────┐
│  Matrix Homeserver (Dendrite)                          │
│  - 消息路由 / 账号管理 / 群聊逻辑                         │
│  - Admin API (账号创建自动化)                            │
└──────┬──────────────┬──────────────┬────────────────────┘
       │              │              │
┌──────┴─────┐ ┌─────┴──────┐ ┌─────┴──────┐
│ Agent A    │ │ Agent B    │ │ Agent C    │
│ (Hermes)   │ │ (Hermes)   │ │ (Hermes)   │
│ matrix-nio │ │ matrix-nio │ │ matrix-nio │
└────────────┘ └────────────┘ └────────────┘
```

## 📦 模块

| 模块 | 路径 | 说明 |
|------|------|------|
| `infrastructure/` | IaC | Terraform + Ansible，PVE 上自动化部署 |
| `matrix/` | 消息服务 | Dendrite Homeserver + Element Web |
| `agent/` | Agent 运行时 | Hermes Agent + matrix-nio SDK |
| `team/` | 团队管理 | Agent 角色定义 + 协作规则 |
| `docs/` | 文档 | 部署指南 + 使用手册 |

## 🚀 快速部署

```bash
# 1. 克隆仓库
git clone https://github.com/mishuchu/ai-team.git
cd ai-team

# 2. 配置 PVE 连接
export PVE_HOST=192.168.x.x
export PVE_USER=root

# 3. 部署基础设施
cd infrastructure/terraform
terraform init
terraform apply

# 4. 配置 Matrix 服务器
cd ../ansible
ansible-playbook -i inventory playbook-matrix.yml

# 5. 部署 Agent
ansible-playbook -i inventory playbook-agents.yml
```

## 📋 前提条件

- PVE 9.x 环境（任意 PVE 机器）
- Terraform >= 1.6
- Ansible >= 2.15
- 至少 4GB RAM 可用

## 🛠️ 技术栈

- **Homeserver**: Dendrite (Go, 高性能低资源)
- **Web UI**: Element Web (TypeScript, 官方客户端)
- **Bot SDK**: matrix-nio (Python, 异步)
- **IaC**: Terraform + Ansible
- **Agent**: Hermes (Python)

## 📄 License

MIT