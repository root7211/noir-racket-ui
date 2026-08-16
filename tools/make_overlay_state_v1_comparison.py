#!/usr/bin/env python3
"""Compose real X11/Vulkan overlay_state_plan endpoints into an auditable comparison."""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out"
INPUTS = [
    ("Closed / initial state", OUT / "material-overlay-hidden-v1.png"),
    ("Open / fixed overlay", OUT / "material-overlay-open-v1.png"),
    ("Closed / Escape action", OUT / "material-overlay-escape-closed-v1.png"),
]
OUTPUT = OUT / "material-overlay-state-v1-comparison.png"


def font(size: int) -> ImageFont.ImageFont:
    for candidate in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",):
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def main() -> None:
    frames = [(label, Image.open(path).convert("RGB")) for label, path in INPUTS]
    width, height = frames[0][1].size
    scale = 0.5
    thumb = (int(width * scale), int(height * scale))
    crop = (250, 130, 1160, 470)
    crop_scale = 0.72
    crop_size = (int((crop[2] - crop[0]) * crop_scale), int((crop[3] - crop[1]) * crop_scale))
    pad, header, gap = 28, 42, 22
    board_w = pad * 2 + thumb[0] * 3 + gap * 2
    board_h = header + thumb[1] + 32 + crop_size[1] + pad * 2
    board = Image.new("RGB", (board_w, board_h), "#141821")
    draw = ImageDraw.Draw(board)
    title_font, label_font = font(24), font(17)
    draw.text((pad, 10), "overlay_state_plan v1 · real X11/Vulkan endpoints", font=title_font, fill="#f4efff")
    for index, (label, image) in enumerate(frames):
        x = pad + index * (thumb[0] + gap)
        draw.text((x, header), label, font=label_font, fill="#d8d5df")
        board.paste(image.resize(thumb, Image.Resampling.LANCZOS), (x, header + 24))
        zoom_y = header + 24 + thumb[1] + 30
        zoom = image.crop(crop).resize(crop_size, Image.Resampling.LANCZOS)
        board.paste(zoom, (x, zoom_y))
        draw.rectangle((x, zoom_y, x + crop_size[0] - 1, zoom_y + crop_size[1] - 1), outline="#777281", width=1)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    board.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
