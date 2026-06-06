"""Tailscale channel driver."""
import subprocess
import time
import re
from typing import Optional
from .base import BaseChannel, ChannelStatus


class TailscaleChannel(BaseChannel):
    """Tailscale WireGuard tunnel channel."""

    def __init__(self, name: str, priority: int, config: dict):
        super().__init__(name, priority, config)
        self.auth_key = config.get("auth_key", "")
        self.accept_routes = config.get("accept_routes", True)
        self.exit_node = config.get("exit_node", False)
        self._login_url: Optional[str] = None

    def connect(self) -> bool:
        """Connect to Tailscale network."""
        if self.is_connected():
            return True

        cmd = ["tailscale", "up", "--json", "--authkey", self.auth_key]
        if self.accept_routes:
            cmd.append("--accept-routes")
        if self.exit_node:
            cmd.append("--exit-node")

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                self.state.mark_active(0)
                return True
            else:
                self.state.mark_failed(result.stderr)
                return False
        except Exception as e:
            self.state.mark_failed(str(e))
            return False

    def disconnect(self) -> bool:
        """Disconnect from Tailscale network."""
        try:
            result = subprocess.run(["tailscale", "down"], capture_output=True, text=True, timeout=10)
            return result.returncode == 0
        except Exception:
            return False

    def health_check(self) -> tuple[bool, float, str]:
        """Check Tailscale connectivity."""
        self.state.mark_checking()
        start = time.time()

        try:
            # Method 1: Check if tailscale interface exists
            result = subprocess.run(
                ["ip", "link", "show", "tailscale0"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode != 0:
                return False, 0, "tailscale0 interface not found"

            # Method 2: Check tailscale status
            result = subprocess.run(
                ["tailscale", "status", "--json"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode != 0:
                return False, 0, "tailscale status failed"

            import json
            status = json.loads(result.stdout)
            if not status.get("BackendState") == "Running":
                return False, 0, "Tailscale not running"

            # Method 3: Ping control node to measure latency
            target = self.config.get("health_check", {}).get("target", "100.64.0.1")
            ping_result = subprocess.run(
                ["ping", "-c", "1", "-W", "3", target],
                capture_output=True, text=True, timeout=5
            )
            latency = 0.0
            if ping_result.returncode == 0:
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
        """Check if Tailscale is connected."""
        try:
            result = subprocess.run(
                ["tailscale", "status", "--json"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode != 0:
                return False
            import json
            status = json.loads(result.stdout)
            return status.get("BackendState") == "Running"
        except Exception:
            return False
