#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/assets/fontc/noir-desktop-sans-18.spec.json"
OUT="$ROOT/out/fontc/noir-desktop-sans-18"
REPEAT="$(mktemp -d)"
SMOKE="$(mktemp --suffix=.rkt)"
SCENE="$(mktemp --suffix=.scene.json)"
BAD="$(mktemp --suffix=.rkt)"
trap 'rm -rf "$REPEAT" "$SMOKE" "$SCENE" "$BAD"' EXIT

python3 "$ROOT/tools/noir_fontc.py" "$SPEC" --out "$OUT" >/tmp/noir-fontc-theme-first.json
python3 "$ROOT/tools/noir_fontc.py" "$SPEC" --out "$REPEAT" >/tmp/noir-fontc-theme-repeat.json
cmp "$OUT/atlas.r8" "$REPEAT/atlas.r8"
cmp "$OUT/manifest.json" "$REPEAT/manifest.json"

python3 - "$OUT/manifest.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
assert manifest['schema'] == 'noir-font-asset-manifest-v1'
assert manifest['revision'] == 1
assert manifest['renderer_kind'] == 'atlas-gray'
assert manifest['glyph_count'] == 95
assert len(manifest['atlas_sha256']) == 64
assert len(manifest['font_sha256']) == 64
assert manifest['metrics']['line_height'] > manifest['metrics']['pixel_size']
print('fontc: deterministic 95-glyph desktop manifest accepted')
PY

cat >"$SMOKE" <<'EOF'
#lang noir/ui
(noir-app
 (theme noir-desktop
   (color canvas "#0E1117" surface "#171B24" text "#F4F7FB" accent "#4C8DFF")
   (space xs 4 sm 8 md 12 lg 16 xl 24 page 32)
   (type caption 13 body 15 label 16 title 28 display 36)
   (radius control 6 card 10 panel 14 overlay 18))
 (state [detail-damage 0])
 (action open-log-detail (set detail-damage (+ detail-damage 1)))
 (stack #:id dashboard #:height 80 #:background (theme-color canvas) #:radius (theme-radius panel)
   (text #:id anchor #:height 40 #:background (theme-color surface) #:dynamic detail-damage #:max-chars 8)
   (button #:id trigger #:height 30 #:background (theme-color accent) "RUN" #:on open-log-detail)))
EOF
NOIR_ENTRY_MODULE="$SMOKE" PLTCOLLECTS="$ROOT:" racket "$ROOT/tools/export-dashboard.rkt" "$SCENE" >/tmp/noir-fontc-theme-export.log 2>&1
python3 - "$SCENE" <<'PY'
import json, sys
root = json.load(open(sys.argv[1]))['root']['props']
assert root['#:background'] == [14/255, 17/255, 23/255, 1.0]
assert root['#:radius'] == 14
print('theme: tokens lowered to fixed RGBA and radius constants')
PY

cat >"$BAD" <<'EOF'
#lang noir/ui
(noir-app
 (theme noir-desktop
   (color canvas "#0E1117")
   (space xs 4)
   (type body 15)
   (radius card 10))
 (state [detail-damage 0])
 (stack #:id dashboard #:height 40 #:background (theme-color missing)))
EOF
if PLTCOLLECTS="$ROOT:" racket "$BAD" >/tmp/noir-fontc-theme-bad.log 2>&1; then
  echo 'expected unknown theme token to fail' >&2
  exit 1
fi
grep -q 'unknown color token missing' /tmp/noir-fontc-theme-bad.log

echo 'fontc/theme: all build-time oracles passed'
