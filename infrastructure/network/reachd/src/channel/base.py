"""Channel abstract base class."""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from typing import Optional
import time


class ChannelStatus(Enum):
    UNKNOWN = "unknown"
    ACTIVE = "active"
    STANDBY = "standby"
    FAILED = "failed"
    CHECKING = "checking"


@dataclass
class ChannelState:
    name: str
    status: ChannelStatus
    priority: int
    latency_ms: Optional[float] = None
    last_check: Optional[float] = None
    error: Optional[str] = None
    metadata: dict = None

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}

    @property
    def is_healthy(self) -> bool:
        return self.status == ChannelStatus.ACTIVE

    def mark_checking(self):
        self.status = ChannelStatus.CHECKING
        self.last_check = time.time()

    def mark_active(self, latency_ms: float):
        self.status = ChannelStatus.ACTIVE
        self.latency_ms = latency_ms
        self.last_check = time.time()
        self.error = None

    def mark_failed(self, error: str):
        self.status = ChannelStatus.FAILED
        self.last_check = time.time()
        self.error = error

    def mark_standby(self):
        self.status = ChannelStatus.STANDBY


class BaseChannel(ABC):
    """Abstract base class for all channel drivers."""

    def __init__(self, name: str, priority: int, config: dict):
        self.name = name
        self.priority = priority
        self.config = config
        self.state = ChannelState(name=name, status=ChannelStatus.UNKNOWN, priority=priority)

    @abstractmethod
    def connect(self) -> bool:
        """Establish connection on this channel. Returns True if successful."""
        pass

    @abstractmethod
    def disconnect(self) -> bool:
        """Disconnect this channel. Returns True if successful."""
        pass

    @abstractmethod
    def health_check(self) -> tuple[bool, float, str]:
        """
        Check channel health.
        Returns: (is_healthy, latency_ms, error_msg)
        """
        pass

    @abstractmethod
    def is_connected(self) -> bool:
        """Check if channel is currently connected."""
        pass

    def get_state(self) -> ChannelState:
        return self.state

    def __repr__(self):
        return f"<{self.__class__.__name__} name={self.name} status={self.state.status.value}>"
