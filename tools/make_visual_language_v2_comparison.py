#!/usr/bin/env python3
"""Create deterministic before/after comparison plates for Visual Language v2."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out"
FONT_REGULAR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


def make(before_name: str, after_name: str, output_name: str, title: str) -> None:
    before = Image.open(OUT / before_name).convert("RGB")
    after = Image.open(OUT / after_name).convert("RGB")
    if before.size != (1280, 720) or after.size != (1280, 720):
        raise ValueError(f"comparison expects 1280x720 inputs, got {before.size} and {after.size}")

    margin = 24
    gap = 24
    header = 82
    footer = 38
    width = margin * 2 + before.width * 2 + gap
    height = header + before.height + footer
    canvas = Image.new("RGB", (width, height), "#05070B")
    draw = ImageDraw.Draw(canvas)

    draw.text((margin, 14), title, fill="#C8D5E8", font=font(FONT_BOLD, 24))
    draw.text((margin, 48), "BEFORE — PAGE 3 BODY + VISUAL V1", fill="#8FA1BA", font=font(FONT_BOLD, 15))
    after_x = margin + before.width + gap
    draw.text((after_x, 48), "AFTER — COMPILED VISUAL LANGUAGE V2", fill="#67A4FF", font=font(FONT_BOLD, 15))

    image_y = header
    canvas.paste(before, (margin, image_y))
    canvas.paste(after, (after_x, image_y))
    draw.rectangle((margin - 1, image_y - 1, margin + before.width, image_y + before.height), outline="#26344A", width=1)
    draw.rectangle((after_x - 1, image_y - 1, after_x + after.width, image_y + after.height), outline="#174F9E", width=2)

    footer_y = image_y + before.height + 10
    draw.text((margin, footer_y), "Same 1280×720 X11/Vulkan path; runtime list and action ABIs preserved.",
              fill="#586A83", font=font(FONT_REGULAR, 13))
    canvas.save(OUT / output_name, optimize=True)


make(
    "log-browser-page3-tabular.png",
    "log-browser-visual-language-v2.png",
    "log-browser-visual-v1-v2-comparison.png",
    "NOIR LOG BROWSER — VISUAL EVOLUTION",
)
make(
    "realtime-monitor-page3-tabular.png",
    "realtime-monitor-visual-language-v2.png",
    "realtime-monitor-visual-v1-v2-comparison.png",
    "NOIR REALTIME MONITOR — VISUAL EVOLUTION",
)
print("visual-language-v2 comparison plates: PASS")
