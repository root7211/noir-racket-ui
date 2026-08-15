#!/usr/bin/env python3
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
source = root / "out/log-browser-ui/02-tail-selected-detail.png"
image = Image.open(source)
# Title through detail, excluding empty top/bottom bands; nearest preserves atlas pixels.
crop = image.crop((24, 58, 620, 310))
crop.resize((crop.width * 3, crop.height * 3), Image.Resampling.NEAREST).save(root / "out/log-browser-ui/03-tail-selected-detail-3x.png")
