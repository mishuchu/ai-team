"""SSH Tunnel channel driver."""
import subprocess
import time
import socket
from typing import Optional
from .base import BaseChannel, ChannelStatus


class SSHChannel(BaseChannel):
    """SSH reverse tunnel channel for backup connectivity."""

    def __init__(self, name: str, priority: int, config: dict):
        super().__init__(name, priority, config)
        self.host = config.get("host", "")
        self.port = config.get("port", 22)
        self.user = config.get("user", "reachd")
        self.key_path = config.get("key_path", "/run/secrets/ssh_key")
        self.keepalive = config.get("keepalive", 10)
        self.reverse_tunnel = config.get("reverse_tunnel", {})
        self._process: Optional[subprocess.Popen] = None
        self.local_port = self.reverse_tunnel.get("local_port", 8080)
        self.remote_port = self.reverse_tunnel.get("remote_port", 22022)

    def connect(self) -> bool:
        """Establish SSH tunnel."""
        if self.is_connected():
            return True

        if not self.reverse_tunnel.get("enabled", False):
            # Just verify SSH connectivity
            return self._test_ssh_connection()

        cmd = [
            "ssh", "-o", "StrictHostKeyChecking=no",
            "-o", "ServerAliveInterval=" + str(self.keepalive),
            "-o", "ServerAliveCountMax=3",
            "-o", "BatchMode=yes",
            "-N", "-T",
            "-R", f"{self.remote_port}:localhost:{self.local_port}",
            "-i", self.key_path,
            "-p", str(self.port),
            f"{self.user}@{self.host}",
        ]

        try:
            self._process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            time.sleep(2)
            if self._process.poll() is None:
                self.state.mark_active(0)
                return True
            else:
                stdout, stderr = self._process.communicate(timeout=5)
                self.state.mark_failed(f"SSH tunnel failed: {stderr}")
                return False
        except Exception as e:
            self.state.mark_failed(str(e))
            return False

    def disconnect(self) -> bool:
        """Close SSH tunnel."""
        if self._process:
            self._process.terminate()
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
            self._process = None
        return True

    def health_check(self) -> tuple[bool, float, str]:
        """Check SSH connectivity."""
        self.state.mark_checking()
        start = time.time()

        try:
            # TCP connect to SSH port
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((self.host, self.port))
            sock.close()

            if result != 0:
                return False, 0, f"cannot connect to {self.host}:{self.port}"

            # Measure latency
            latency_start = time.time()
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            sock.connect((self.host, self.port))
            sock.close()
            latency = (time.time() - latency_start) * 1000

            self.state.mark_active(latency)
            return True, latency, ""

        except socket.timeout:
            return False, 0, "SSH connection timeout"
        except Exception as e:
            return False, 0, str(e)

    def is_connected(self) -> bool:
        """Check if SSH tunnel is active."""
        if self._process is None:
            return False
        return self._process.poll() is None

    def _test_ssh_connection(self) -> bool:
        """Test basic SSH connectivity without tunnel."""
        try:
            result = subprocess.run(
                [
                    "ssh", "-o", "StrictHostKeyChecking=no",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-i", self.key_path,
                    "-p", str(self.port),
                    f"{self.user}@{self.host}", "echo", "ok"
                ],
                capture_output=True, text=True, timeout=10
            )
            return result.returncode == 0 and "ok" in result.stdout
        except Exception:
            return False
