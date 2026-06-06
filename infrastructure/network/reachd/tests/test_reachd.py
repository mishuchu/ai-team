"""reachd 单元测试."""
import pytest
import time
from channel.base import BaseChannel, ChannelState, ChannelStatus, create_channel


class MockChannel(BaseChannel):
    """Mock channel for testing."""

    def __init__(self, name: str, priority: int, config: dict, healthy: bool = True):
        super().__init__(name, priority, config)
        self._healthy = healthy
        self._connected = False

    def connect(self) -> bool:
        self._connected = True
        return True

    def disconnect(self) -> bool:
        self._connected = False
        return True

    def health_check(self) -> tuple[bool, float, str]:
        if self._healthy:
            return True, 12.5, ""
        return False, 0, "mock failure"

    def is_connected(self) -> bool:
        return self._connected


class TestChannelState:
    def test_initial_state(self):
        state = ChannelState(name="test", status=ChannelStatus.UNKNOWN, priority=1)
        assert state.name == "test"
        assert state.status == ChannelStatus.UNKNOWN
        assert state.priority == 1
        assert state.latency_ms is None
        assert state.error is None
        assert not state.is_healthy

    def test_mark_active(self):
        state = ChannelState(name="test", status=ChannelStatus.UNKNOWN, priority=1)
        state.mark_active(25.5)
        assert state.status == ChannelStatus.ACTIVE
        assert state.latency_ms == 25.5
        assert state.last_check is not None
        assert state.error is None
        assert state.is_healthy

    def test_mark_failed(self):
        state = ChannelState(name="test", status=ChannelStatus.ACTIVE, priority=1)
        state.mark_failed("connection timeout")
        assert state.status == ChannelStatus.FAILED
        assert state.error == "connection timeout"
        assert not state.is_healthy


class TestCreateChannel:
    def test_create_tailscale(self):
        ch = create_channel("tailscale", priority=1, config={})
        assert ch.name == "tailscale"
        assert ch.priority == 1

    def test_create_cloudflare(self):
        ch = create_channel("cloudflare", priority=2, config={})
        assert ch.name == "cloudflare"
        assert ch.priority == 2

    def test_create_ssh(self):
        ch = create_channel("ssh", priority=3, config={})
        assert ch.name == "ssh"
        assert ch.priority == 3

    def test_unknown_channel(self):
        with pytest.raises(ValueError, match="Unknown channel type"):
            create_channel("unknown", priority=1, config={})


class TestMockChannel:
    def test_connect_disconnect(self):
        ch = MockChannel("mock", priority=1, config={})
        assert not ch.is_connected()

        assert ch.connect()
        assert ch.is_connected()

        assert ch.disconnect()
        assert not ch.is_connected()

    def test_health_check_healthy(self):
        ch = MockChannel("mock", priority=1, config={}, healthy=True)
        is_healthy, latency, error = ch.health_check()
        assert is_healthy
        assert latency == 12.5
        assert error == ""

    def test_health_check_unhealthy(self):
        ch = MockChannel("mock", priority=1, config={}, healthy=False)
        is_healthy, latency, error = ch.health_check()
        assert not is_healthy
        assert error == "mock failure"


class TestChannelPriority:
    def test_priority_order(self):
        channels = [
            create_channel("ssh", priority=3, config={}),
            create_channel("tailscale", priority=1, config={}),
            create_channel("cloudflare", priority=2, config={}),
        ]
        channels.sort(key=lambda c: c.priority)
        assert [c.name for c in channels] == ["tailscale", "cloudflare", "ssh"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
