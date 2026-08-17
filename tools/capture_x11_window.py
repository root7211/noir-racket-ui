#!/usr/bin/env python3
"""Capture one X11 window using Pillow's XCB ImageGrab backend."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from PIL import ImageGrab


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: capture_x11_window.py WINDOW_ID OUTPUT.png")
    window_id, output = sys.argv[1:]
    geometry = subprocess.check_output(
        ["xdotool", "getwindowgeometry", "--shell", window_id], text=True, env=os.environ
    )
    values = {}
    for line in geometry.splitlines():
        key, value = line.split("=", 1)
        values[key] = int(value)
    left, top = values["X"], values["Y"]
    right, bottom = left + values["WIDTH"], top + values["HEIGHT"]
    image = ImageGrab.grab(bbox=(left, top, right, bottom), xdisplay=os.environ.get("DISPLAY"))
    destination = Path(output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination)
    print(destination)


if __name__ == "__main__":
    main()
