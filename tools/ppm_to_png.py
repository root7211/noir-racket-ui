import sys
from pathlib import Path
from PIL import Image

if len(sys.argv) < 2:
    raise SystemExit("usage: ppm_to_png.py INPUT.ppm [OUTPUT.png]")

source = Path(sys.argv[1])
target = Path(sys.argv[2]) if len(sys.argv) > 2 else source.with_suffix('.png')
with Image.open(source) as image:
    image.save(target)
print(target)
