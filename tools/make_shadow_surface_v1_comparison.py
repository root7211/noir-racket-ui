#!/usr/bin/env python3
"""Build a deterministic before/after board for shadow_surface_plan v1 evidence."""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out"
BEFORE = OUT / "material-profile-dashboard-before-shadow-v1.png"
AFTER = OUT / "material-profile-dashboard-v1.png"
TARGET = OUT / "material-profile-shadow-v1-comparison.png"


def font(size: int) -> ImageFont.ImageFont:
    for path in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ]:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def label(draw: ImageDraw.ImageDraw, text: str, xy: tuple[int, int], size: int, fill: str) -> None:
    draw.text(xy, text, fill=fill, font=font(size))


def main() -> None:
    before = Image.open(BEFORE).convert("RGB")
    after = Image.open(AFTER).convert("RGB")
    if before.size != after.size:
        raise SystemExit("comparison frames must have identical dimensions")
    width, height = before.size
    board = Image.new("RGB", (width * 2 + 48, height + 174), "#111827")
    draw = ImageDraw.Draw(board)
    label(draw, "Noir Material Profile — shadow_surface_plan v1", (28, 22), 25, "#f8fafc")
    label(draw, "Same X11/Vulkan scene; elevation layers are compiler-emitted immutable SDF quads.", (28, 59), 15, "#cbd5e1")
    board.paste(before, (0, 112))
    board.paste(after, (width + 48, 112))
    label(draw, "Before — rounded surfaces only", (28, 83), 16, "#cbd5e1")
    label(draw, "After — fixed two-layer shadows", (width + 76, 83), 16, "#d8b4fe")

    # The crop emphasizes the perimeter between upper and lower elevated cards.
    crop_box = (210, 92, 1248, 660)
    crop_before = before.crop(crop_box).resize((519, 284), Image.Resampling.NEAREST)
    crop_after = after.crop(crop_box).resize((519, 284), Image.Resampling.NEAREST)
    overlay_y = height - 9
    board.paste(crop_before, (28, overlay_y - 284))
    board.paste(crop_after, (width + 76, overlay_y - 284))
    draw.rectangle((26, overlay_y - 286, 549, overlay_y + 2), outline="#94a3b8", width=2)
    draw.rectangle((width + 74, overlay_y - 286, width + 597, overlay_y + 2), outline="#d8b4fe", width=2)
    label(draw, "Enlarged card-perimeter crop", (34, overlay_y - 279), 12, "#ffffff")
    label(draw, "Enlarged card-perimeter crop", (width + 82, overlay_y - 279), 12, "#ffffff")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    board.save(TARGET)
    print(TARGET)


if __name__ == "__main__":
    main()
