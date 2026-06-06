#!/bin/bash
# reachd 信道切换管理脚本
# 负责：健康检测 → failover → 更新状态文件 →通知代理层

set -e

CONFIG_FILE="${1:-config/channels.yaml}"
STATE_FILE="${STATE_FILE:-/tmp/reachd_active_channel}"
LOG_FILE="${LOG_FILE:-/tmp/reachd.log}"

# 默认值
INTERVAL=10
TIMEOUT=5

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# 检查 tailscale 状态
check_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        echo "tailscale not installed"
        return1
    fi

    if ! ip link show tailscale0 &>/dev/null; then
        echo "tailscale0 interface not found"
        return 1
    fi

    local status
    status=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState','Unknown'))" 2>/dev/null || echo "Unknown")
    if [ "$status" != "Running" ]; then
        echo "Tailscale status: $status"
        return 1
    fi

    return 0
}

# 检查 cloudflare tunnel 状态
check_cloudflare() {
    if ! command -v cloudflared &>/dev/null; then
        echo "cloudflared not installed"
        return 1
    fi

    if curl -s -f -m 3 http://localhost:35721/metrics &>/dev/null; then
        return 0
    fi
    echo "cloudflared metrics not responding"
    return 1
}

# 检查 SSH 隧道状态
check_ssh() {
    local host="${SSH_HOST:-}"
    local port="${SSH_PORT:-22}"

    if [ -z "$host" ]; then
        echo "SSH_HOST not set"
        return 1
    fi

    if nc -z -w5 "$host" "$port" 2>/dev/null; then
        return 0
    fi
    echo "cannot connect to $host:$port"
    return 1
}

# 测量延迟
measure_latency() {
    local target="$1"
    local latency
    latency=$(ping -c 1 -W 3 "$target" 2>/dev/null | python3 -c "import sys,re; m=re.search(r'time=(\d+\.?\d*)', sys.stdin.read()); print(m.group(1) if m else '0')" 2>/dev/null || echo "0")
    echo "$latency"
}

# 获取活跃信道
get_active_channel() {
    local priority=1
    local active=""

    # Tailscale (优先级1)
    if check_tailscale &>/dev/null; then
        log "Tailscale: healthy"
        if [ $priority -le 1 ]; then
            active="tailscale"
            priority=1
        fi
    fi

    # Cloudflare (优先级2)
    if check_cloudflare &>/dev/null; then
        log "Cloudflare Tunnel: healthy"
        if [ $priority -le 2 ]; then
            active="cloudflare"
            priority=2
        fi
    fi

    # SSH (优先级3)
    if check_ssh &>/dev/null; then
        log "SSH Tunnel: healthy"
        if [ $priority -le 3 ]; then
            active="ssh"
            priority=3
        fi
    fi

    if [ -z "$active" ]; then
        log "ERROR: No healthy channel available!"
        echo "none" > "$STATE_FILE"
        return 1
    fi

    echo "$active" > "$STATE_FILE"
    log "Active channel: $active"
}

# 主循环
main() {
    log "reachd channel manager started"

    while true; do
        get_active_channel
        sleep "$INTERVAL"
    done
}

main "$@"
