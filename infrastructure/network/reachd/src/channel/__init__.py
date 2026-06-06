"""reachd channel drivers."""
from .base import BaseChannel, ChannelState, ChannelStatus
from .tailscale import TailscaleChannel
from .cloudflare import CloudflareChannel
from .ssh import SSHChannel

CHANNEL_REGISTRY = {
    "tailscale": TailscaleChannel,
    "cloudflare": CloudflareChannel,
    "ssh": SSHChannel,
}


def create_channel(name: str, priority: int, config: dict) -> BaseChannel:
    """Factory to create a channel by name."""
    channel_cls = CHANNEL_REGISTRY.get(name)
    if not channel_cls:
        raise ValueError(f"Unknown channel type: {name}. Available: {list(CHANNEL_REGISTRY.keys())}")
    return channel_cls(name=name, priority=priority, config=config)


__all__ = [
    "BaseChannel", "ChannelState", "ChannelStatus",
    "TailscaleChannel", "CloudflareChannel", "SSHChannel",
    "create_channel",
]
