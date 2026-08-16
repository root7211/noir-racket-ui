#!/usr/bin/env python3
"""Build a deterministic before/after board for page-2 baseline placement."""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out"
BEFORE = OUT / "material-profile-dashboard-before-baseline-v1.png"
AFTER = OUT / "material-profile-dashboard-v1.png"
OUTPUT = OUT / "material-profile-baseline-before-after.png"


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size)


def label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, color: tuple[int, int, int]) -> None:
    draw.text(xy, text, fill=color, font=font(24))


def main() -> None:
    before = Image.open(BEFORE).convert("RGB")
    after = Image.open(AFTER).convert("RGB")
    if before.size != after.size:
        raise SystemExit("input dimensions differ")

    # Keep full real frames and add two nearest-neighbour enlarged title crops where
    # the prior top-alignment defect is most evident.
    crop = (236, 120, 718, 280)
    before_crop = before.crop(crop).resize((964, 320), Image.Resampling.NEAREST)
    after_crop = after.crop(crop).resize((964, 320), Image.Resampling.NEAREST)
    width = 32 + before.width + 32 + after.width + 32
    height = 52 + before.height + 36 + 32 + 320 + 32
    board = Image.new("RGB", (width, height), (17, 22, 31))
    draw = ImageDraw.Draw(board)
    label(draw, (32, 14), "Before: glyph tops forced to one y", (246, 185, 205))
    label(draw, (32 + before.width + 32, 14), "After: manifest-bearing baseline", (182, 225, 201))
    board.paste(before, (32, 52))
    board.paste(after, (32 + before.width + 32, 52))
    label(draw, (32, 52 + before.height + 38), "Service health — 2× pixel crop", (225, 230, 238))
    board.paste(before_crop, (32, 52 + before.height + 76))
    board.paste(after_crop, (32 + 964 + 32, 52 + before.height + 76))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    board.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
