from PIL import Image
import sys

if len(sys.argv) != 3:
    raise SystemExit('usage: sample_pixels.py partial.png oracle.png')
partial = Image.open(sys.argv[1]).convert('RGB')
oracle = Image.open(sys.argv[2]).convert('RGB')
for y in range(274, 280):
    print(y, [(x, partial.getpixel((x, y)), oracle.getpixel((x, y))) for x in (411, 420, 500, 585)])
