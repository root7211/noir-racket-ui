#!/usr/bin/env python3
"""Create deterministic v2-to-v3 rounded-surface comparison plates."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out"
REGULAR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def face(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


def make(before_name: str, after_name: str, output_name: str, title: str) -> None:
    before = Image.open(OUT / before_name).convert("RGB")
    after = Image.open(OUT / after_name).convert("RGB")
    if before.size != (1280, 720) or after.size != (1280, 720):
        raise ValueError(f"expected 1280x720 source frames, got {before.size} and {after.size}")
    margin, gap, header, footer = 24, 24, 82, 42
    width = margin * 2 + before.width * 2 + gap
    height = header + before.height + footer
    canvas = Image.new("RGB", (width, height), "#05070B")
    draw = ImageDraw.Draw(canvas)
    after_x = margin + before.width + gap
    image_y = header
    draw.text((margin, 14), title, fill="#C8D5E8", font=face(BOLD, 24))
    draw.text((margin, 48), "BEFORE — VISUAL LANGUAGE V2 / HARD RECTANGLES", fill="#8FA1BA", font=face(BOLD, 15))
    draw.text((after_x, 48), "AFTER — ROUNDED SURFACE V3 / 1PX SDF AA", fill="#67D6C6", font=face(BOLD, 15))
    canvas.paste(before, (margin, image_y))
    canvas.paste(after, (after_x, image_y))
    draw.rectangle((margin - 1, image_y - 1, margin + before.width, image_y + before.height), outline="#26344A", width=1)
    draw.rectangle((after_x - 1, image_y - 1, after_x + after.width, image_y + after.height), outline="#1F8E80", width=2)
    draw.text((margin, image_y + before.height + 11),
              "Same 1280×720 Scene geometry, text assets, list actions and Vulkan/X11 executor; only compiler-proved rounded metadata changes.",
              fill="#8093AA", font=face(REGULAR, 13))
    canvas.save(OUT / output_name, optimize=True)


make("log-browser-visual-language-v2.png", "log-browser-rounded-v3.png",
     "log-browser-rounded-v2-v3-comparison.png", "NOIR LOG BROWSER — COMPILED SURFACE EVOLUTION")
make("realtime-monitor-visual-language-v2.png", "realtime-monitor-rounded-v3.png",
     "realtime-monitor-rounded-v2-v3-comparison.png", "NOIR REALTIME MONITOR — COMPILED SURFACE EVOLUTION")
print("rounded-surface-v3 comparison plates: PASS")
