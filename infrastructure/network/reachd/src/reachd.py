"""reachd — 自组织自愈合多信道网络中间件主程序."""
import argparse
import logging
import sys
import time
import json
import signal
from pathlib import Path
from typing import Optional

from channel import create_channel, CHANNEL_REGISTRY
from health.checker import HealthChecker, HealthResult
from channel.base import ChannelStatus

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("reachd")


class ChannelManager:
    """Manages all channels and handles failover."""

    def __init__(self, channels_config: list):
        self.channels = []
        for cfg in channels_config:
            ch = create_channel(
                name=cfg["name"],
                priority=cfg["priority"],
                config=cfg.get("config", {})
            )
            self.channels.append(ch)
        # Sort by priority
        self.channels.sort(key=lambda c: c.priority)

        self.active_channel = self._find_best_channel()
        logger.info(f"ChannelManager initialized, active={self.active_channel.name if self.active_channel else None}")

    def _find_best_channel(self):
        """Find the best available channel (highest priority, healthy)."""
        for ch in self.channels:
            if ch.state.status == ChannelStatus.ACTIVE:
                return ch
        return None

    def on_health_result(self, result: HealthResult):
        """Handle health check result and trigger failover if needed."""
        channel = next((c for c in self.channels if c.name == result.channel_name), None)
        if not channel:
            return

        # Update state
        if result.is_healthy:
            channel.state.mark_active(result.latency_ms)
        else:
            channel.state.mark_failed(result.error)

        # Check if active channel failed
        if self.active_channel and self.active_channel.name == result.channel_name:
            if not result.is_healthy:
                logger.warning(f"Active channel {result.channel_name} failed: {result.error}")
                self._failover()

    def _failover(self):
        """Switch to next best available channel."""
        old = self.active_channel
        new_channel = self._find_best_channel()

        if new_channel and new_channel.name != old.name:
            logger.info(f"Failover: {old.name} -> {new_channel.name}")
            self.active_channel = new_channel
            # TODO: notify proxy layer
        elif not new_channel:
            logger.error("FAILOVER FAILED: No healthy channel available!")
            self.active_channel = None

    def connect_all(self):
        """Connect all channels."""
        for ch in self.channels:
            if ch.config.get("enabled", True):
                try:
                    if ch.connect():
                        logger.info(f"Channel {ch.name} connected")
                    else:
                        logger.warning(f"Channel {ch.name} connect failed")
                except Exception as e:
                    logger.error(f"Channel {ch.name} connect error: {e}")

    def get_status(self) -> dict:
        """Get current status of all channels."""
        return {
            "active_channel": self.active_channel.name if self.active_channel else None,
            "channels": [
                {
                    "name": ch.name,
                    "priority": ch.priority,
                    "status": ch.state.status.value,
                    "latency_ms": ch.state.latency_ms,
                    "last_check": ch.state.last_check,
                    "error": ch.state.error,
                }
                for ch in self.channels
            ]
        }


def load_config(config_path: str) -> dict:
    """Load configuration from YAML file."""
    import yaml
    with open(config_path) as f:
        return yaml.safe_load(f)


def daemon(args):
    """Main daemon loop."""
    config = load_config(args.config)

    # Init channel manager
    manager = ChannelManager(config.get("channels", []))

    # Connect all channels
    manager.connect_all()

    # Start health checker
    global_interval = config.get("health_check", {}).get("interval", 10)
    checker = HealthChecker(
        channels=manager.channels,
        interval=global_interval
    )
    checker.register_callback(manager.on_health_result)
    checker.start()

    # Main loop
    try:
        logger.info("reachd daemon running...")
        while True:
            time.sleep(5)
            # Periodic status log
            status = manager.get_status()
            logger.debug(f"Status: {json.dumps(status, default=str)}")
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        checker.stop()


def status(args):
    """Print current status."""
    config = load_config(args.config)
    manager = ChannelManager(config.get("channels", []))
    status_data = manager.get_status()

    print(f"Active Channel: {status_data['active_channel'] or 'NONE'}")
    print(f"\n{'Channel':<15} {'Priority':<10} {'Status':<12} {'Latency':<10} {'Last Check':<20}")
    print("-" * 70)
    for ch in status_data["channels"]:
        last = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ch["last_check"])) if ch["last_check"] else "never"
        print(f"{ch['name']:<15} {ch['priority']:<10} {ch['status']:<12} {ch['latency_ms']:<10.1f} {last}")


def main():
    parser = argparse.ArgumentParser(description="reachd — 自组织自愈合多信道网络中间件")
    parser.add_argument("-c", "--config", default="config/channels.yaml", help="Config file path")
    subparsers = parser.add_subparsers()

    subparsers.add_parser("daemon", help="Run as daemon").set_defaults(func=daemon)
    subparsers.add_parser("status", help="Show channel status").set_defaults(func=status)

    args = parser.parse_args()
    if hasattr(args, "func"):
        args.func(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
