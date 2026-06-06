# reachd — 自组织自愈合多信道网络中间件

> 让服务可达，上层应用无需关心用的是哪条信道。

##🎯 项目目标

**一句话定位：** 网络可达性中间件——让任何网络环境下的服务器都能可靠地被外部访问，上层应用无需关心底下用哪条信道。

**三个关键词：**
- **自组织**：节点即插即用，自动发现最优信道
- **自愈合**：故障自动切换，上层应用零感知
- **多信道**：Tailscale / Cloudflare Tunnel / SSH 多路冗余

##🔧 解决的问题

| 场景 | 问题 | reachd 解决 |
|------|------|------------|
| 家宽无公网 IP | 无法从外面访问 | 多信道自动穿透 |
| NAT 环境 | 多节点在不同 NAT 后 | 自协调最优路径 |
| 网络不稳定 | 单信道故障导致中断 | 自动 failover |
| 端口暴露 | 想最小化暴露面 | 统一入口，按需暴露 |

## 🏗️ 架构

```
┌─────────────────────────────────────────────────────────────┐
│                       reachd                                │
│                                                             │
│   上层应用 ──► 固定入口 (nginx/vip) ──► 自愈切换 ──► 信道   │
│                                                             │
│   信道层：                                                  │
│   ┌─────────┐   ┌──────────┐   ┌────────┐                │
│   │ Tailscale│   │Cloudflare│   │  SSH   │                │
│   │(首选)   │   │ Tunnel   │   │ Tunnel │                │
│   └─────────┘  └──────────┘   └────────┘                │
│                                                             │
│   信道驱动：                                                │
│   - health/ 健康检测 │
│   - channel/    信道抽象层                                  │
│   - proxy/      入口代理                                     │
└─────────────────────────────────────────────────────────────┘
```

## 📦 模块

| 模块 | 路径 | 说明 |
|------|------|------|
| `channel/` | 信道驱动 | tailscale.py, cloudflare.py, ssh.py |
| `health/` | 健康检测 | checker.py - 定时检测信道可用性 |
| `proxy/` | 入口代理 | nginx.sh - 固定端口反向代理 |
| `config/` | 配置 | channels.yaml - 信道配置 |
| `scripts/` | 脚本 | channel-manager.sh - 信道切换逻辑 |

## 🚀 快速部署

```bash
# 1. 克隆仓库
git clone https://github.com/mishuchu/reachd.git
cd reachd

# 2. 配置信道
cp config/channels.yaml.example config/channels.yaml
vim config/channels.yaml

# 3. 一键启动
docker-compose up -d

# 4. 查看状态
docker exec reachd python src/reachd.py status
```

##⚙️ 配置示例

```yaml
# config/channels.yaml
node:
  id: "pve-node-1"
  name: "PVE Home Lab"

channels:
  - name: tailscale
    enabled: true
    priority: 1
    config:
      # Tailscale auth key (从 https://login.tailscale.io/admin/settings/keys 获取)
      auth_key: "tskey-auth-xxxxx"
      # 退出节点（让流量通过此节点出口）
      exit_node: false

  - name: cloudflare
    enabled: true
    priority: 2
    config:
      # cloudflared tunnel token
      tunnel_token: "xxxxx"

  - name: ssh
    enabled: true
    priority: 3
    config:
      # VPS 公网 IP
      host: "your-vps-ip"
      port: 22
      user: "reachd"
      # SSH key 认证
      key_path: "/run/secrets/ssh_key"

proxy:
  #固定入口端口
  ingress:
    http: 8080
    https: 8443
  upstream:
    # 应用连接这个固定端口，reachd 自动路由到活跃信道
    app_port: 8080
```

##🔌 信道类型

### tailscale (首选)
- **优点**：自动 NAT 穿透，Zero-config，WireGuard 性能
- **依赖**：Tailscale 客户端 + Headscale 控制服务器（或官方 Tailscale）
- **适用**：节点间互相访问

### cloudflare-tunnel (备用)
- **优点**：稳定，全球加速，免费
- **依赖**：Cloudflare 账号 + cloudflared
- **适用**：对外暴露服务

### ssh-tunnel (兜底)
- **优点**：无需额外服务，只要有 SSH即可
- **依赖**：SSH 访问权限
- **适用**：最终兜底方案

## 📊 健康检测

```bash
# 每 10 秒检测一次所有信道
python src/health/checker.py --interval10

# 信道状态
$ reachd status
CHANNEL          STATUS      LATENCY     LAST CHECK
tailscale        active      12ms 2024-01-01 12:00:00
cloudflare       standby 23ms        2024-01-01 12:00:00
ssh              standby     45ms        2024-01-01 12:00:00
```

## 🔄 自动切换逻辑

```
1. 持续检测所有信道健康状态
2. 活跃信道失败 → 自动切换到最高优先级可用信道
3. 原信道恢复 → 可选切回（默认保持当前信道）
4. 所有信道失败 → 告警通知
```

## 📄 License

MIT