"""Health checker for all channels."""
import time
import threading
import logging
from typing import Callable, Optional, List
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class HealthResult:
    channel_name: str
    is_healthy: bool
    latency_ms: float
    error: str
    timestamp: float


class HealthChecker:
    """Periodic health checker for all registered channels."""

    def __init__(self, channels: List, interval: int = 10, timeout: int = 5):
        self.channels = channels
        self.interval = interval
        self.timeout = timeout
        self._results: dict[str, HealthResult] = {}
        self._callbacks: List[Callable] = []
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def register_callback(self, cb: Callable[[HealthResult], None]):
        """Register a callback to be called on each health check result."""
        self._callbacks.append(cb)

    def _check_channel(self, channel) -> HealthResult:
        """Check a single channel and return result."""
        try:
            is_healthy, latency, error = channel.health_check()
            return HealthResult(
                channel_name=channel.name,
                is_healthy=is_healthy,
                latency_ms=latency,
                error=error,
                timestamp=time.time()
            )
        except Exception as e:
            return HealthResult(
                channel_name=channel.name,
                is_healthy=False,
                latency_ms=0,
                error=str(e),
                timestamp=time.time()
            )

    def check_all(self) -> dict[str, HealthResult]:
        """Check all channels and return results."""
        results = {}
        for channel in self.channels:
            result = self._check_channel(channel)
            results[channel.name] = result
            self._results[channel.name] = result

            # Update channel state
            if result.is_healthy:
                channel.state.mark_active(result.latency_ms)
            else:
                channel.state.mark_failed(result.error)

            # Notify callbacks
            for cb in self._callbacks:
                try:
                    cb(result)
                except Exception as e:
                    logger.error(f"Health callback error: {e}")

        return results

    def get_results(self) -> dict[str, HealthResult]:
        """Get latest health check results."""
        return self._results

    def start(self):
        """Start periodic health checking in background thread."""
        if self._thread and self._thread.is_alive():
            return

        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        logger.info(f"Health checker started (interval={self.interval}s)")

    def _run(self):
        """Background loop."""
        while not self._stop_event.is_set():
            self.check_all()
            self._stop_event.wait(self.interval)

    def stop(self):
        """Stop periodic health checking."""
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("Health checker stopped")
