"""Factory for current-platform injector selection."""

from __future__ import annotations

import platform

from mozhi_agent.injection.base import BaseInjector
from mozhi_agent.injection.macos import MacOSInjector
from mozhi_agent.injection.windows import WindowsInjector


def get_injector() -> BaseInjector:
    """Return a supported platform injector instance."""
    system = platform.system().lower()
    if system == "windows":
        return WindowsInjector()
    if system == "darwin":
        return MacOSInjector()
    raise NotImplementedError(f"Unsupported platform for input injection: {system}")
