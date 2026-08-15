from pathlib import Path
import sys
from PIL import Image, ImageChops

if len(sys.argv) != 4:
    raise SystemExit('usage: compare_pngs.py partial.png oracle.png diff.png')

partial = Image.open(sys.argv[1]).convert('RGB')
oracle = Image.open(sys.argv[2]).convert('RGB')
diff = ImageChops.difference(partial, oracle)
bbox = diff.getbbox()
changed = sum(1 for px in diff.getdata() if px != (0, 0, 0))
diff.save(sys.argv[3])
print({'bbox': bbox, 'changed_pixels': changed, 'partial_size': partial.size})
