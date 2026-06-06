#!/bin/bash
# nginx反向代理层 — 固定端口，upstream 自动切换

set -e

INGRESS_HTTP="${INGRESS_HTTP:-8080}"
INGRESS_HTTPS="${INGRESS_HTTPS:-8443}"
APP_PORT="${APP_PORT:-8080}"
STATE_FILE="${STATE_FILE:-/tmp/reachd_active_channel}"

# 等待至少一个信道激活
wait_for_channel() {
    local timeout=30
    local count=0
    while [ ! -f "$STATE_FILE" ] && [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
    done
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No active channel file found, using localhost"
        echo "localhost" > "$STATE_FILE"
    fi
}

# 生成 nginx 配置
generate_nginx_config() {
    local active_channel
    active_channel=$(cat "$STATE_FILE" 2>/dev/null || echo "localhost")

    cat > /tmp/nginx.reachd.conf << EOF
upstream reachd_backend {
    server ${active_channel}:${APP_PORT};
    keepalive 32;
}

server {
    listen ${INGRESS_HTTP};
    server_name _;

    location /health {
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    location / {
        proxy_pass http://reachd_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}

server {
    listen ${INGRESS_HTTPS} ssl;
    server_name _;

    ssl_certificate /etc/nginx/certs/cert.pem;
    ssl_certificate_key /etc/nginx/certs/key.pem;

    location /health {
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    location / {
        proxy_pass http://reachd_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
}

# 重载 nginx
reload_nginx() {
    if nginx -t -c /tmp/nginx.reachd.conf 2>/dev/null; then
        nginx -c /tmp/nginx.reachd.conf -s reload 2>/dev/null || nginx -c /tmp/nginx.reachd.conf
        echo "nginx reloaded with upstream: $(cat $STATE_FILE)"
    else
        echo "ERROR: nginx config invalid"
        nginx -t -c /tmp/nginx.reachd.conf
    fi
}

# 监控信道切换
watch_channel_switch() {
    local last_channel=""
    while true; do
        current_channel=$(cat "$STATE_FILE" 2>/dev/null || echo "")
        if [ "$current_channel" != "$last_channel" ]; then
            echo "[$(date)] Channel switched: $last_channel -> $current_channel"
            generate_nginx_config
            reload_nginx
            last_channel="$current_channel"
        fi
        sleep 2
    done
}

# 主入口
main() {
    mkdir -p /etc/nginx/certs
    wait_for_channel
    generate_nginx_config
    reload_nginx
    watch_channel_switch
}

main "$@"
