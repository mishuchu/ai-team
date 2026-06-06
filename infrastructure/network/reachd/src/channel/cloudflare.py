"""Cloudflare Tunnel channel driver."""
import subprocess
import time
import os
import signal
from typing import Optional
from .base import BaseChannel, ChannelStatus


class CloudflareChannel(BaseChannel):
    """Cloudflare Tunnel (cloudflared) channel."""

    def __init__(self, name: str, priority: int, config: dict):
        super().__init__(name, priority, config)
        self.tunnel_token = config.get("tunnel_token", "")
        self.tunnel_name = config.get("tunnel_name", "reachd-tunnel")
        self.ingress = config.get("ingress", [])
        self._process: Optional[subprocess.Popen] = None

    def connect(self) -> bool:
        """Start cloudflared tunnel."""
        if self.is_connected():
            return True

        cmd = [
            "cloudflared", "tunnel",
            "--token", self.tunnel_token,
            "--no-autoupdate",
            "--metrics", "localhost:35721",
        ]

        try:
            self._process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            # Wait for startup
            time.sleep(3)
            if self._process.poll() is None:
                self.state.mark_active(0)
                return True
            else:
                stdout, stderr = self._process.communicate(timeout=5)
                self.state.mark_failed(f"cloudflared exited: {stderr}")
                return False
        except Exception as e:
            self.state.mark_failed(str(e))
            return False

    def disconnect(self) -> bool:
        """Stop cloudflared tunnel."""
        if self._process:
            self._process.send_signal(signal.SIGTERM)
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
            self._process = None
        return True

    def health_check(self) -> tuple[bool, float, str]:
        """Check Cloudflare Tunnel connectivity."""
        self.state.mark_checking()
        start = time.time()

        try:
            # Check if cloudflared process is running
            if self._process is None or self._process.poll() is not None:
                return False, 0, "cloudflared not running"

            # Check metrics endpoint
            result = subprocess.run(
                ["curl", "-s", "-f", "-m", "3", "http://localhost:35721/metrics"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode != 0:
                return False, 0, "metrics endpoint not responding"

            # Ping cloudflare edge to measure latency
            ping_result = subprocess.run(
                ["ping", "-c", "1", "-W", "3", "162.159.36.1"],
                capture_output=True, text=True, timeout=5
            )
            latency = 0.0
            if ping_result.returncode == 0:
                import re
                match = re.search(r"time=(\d+\.?\d*)\s*ms", ping_result.stdout)
                if match:
                    latency = float(match.group(1))

            elapsed = (time.time() - start) * 1000
            self.state.mark_active(latency if latency > 0 else elapsed)
            return True, latency if latency > 0 else elapsed, ""

        except subprocess.TimeoutExpired:
            return False, 0, "health check timeout"
        except Exception as e:
            return False, 0, str(e)

    def is_connected(self) -> bool:
        """Check if Cloudflare Tunnel is connected."""
        return self._process is not None and self._process.poll() is None
