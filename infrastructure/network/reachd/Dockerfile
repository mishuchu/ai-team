FROM python:3.11-slim

WORKDIR /app

# 系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    iputils-ping \
    iproute2 \
    netcat-openbsd \
    curl \
    dnsutils \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Tailscale (official repo)
RUN curl -fsSL https://tailscale.com/install.sh | sh

# cloudflared
RUN curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# Python依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 代码
COPY src/ ./src/
COPY config/ ./config/
COPY scripts/ ./scripts/

# 非 root 运行
RUN useradd -m -u 1000 reachd && chown -R reachd:reachd /app
USER reachd

CMD ["python", "src/reachd.py", "daemon", "-c", "config/channels.yaml"]
