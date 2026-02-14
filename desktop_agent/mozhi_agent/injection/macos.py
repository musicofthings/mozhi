"""macOS Claude Desktop injection via AppleScript System Events."""

from __future__ import annotations

import subprocess

from mozhi_agent.injection.base import BaseInjector


class MacOSInjector(BaseInjector):
    """Inject text to Claude Desktop on macOS."""

    def inject(self, text: str, press_enter: bool = True) -> None:
        escaped = text.replace('"', '\\"')
        script = [
            'tell application "Claude" to activate',
            'tell application "System Events"',
            f'keystroke "{escaped}"',
        ]
        if press_enter:
            script.append('key code 36')
        script.append('end tell')
        subprocess.run(["osascript", "-e", "\n".join(script)], check=True)
