#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SPEC="$ROOT/assets/fontc/noir-table-body-mono-16.spec.json"
OUT="$ROOT/assets/fontc/noir-table-body-mono-16"
TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

cd "$ROOT"
python3 tools/noir_fontc.py "$SPEC" --out "$TMP/a" >/tmp/noir-tabular-font-build-a.json
python3 tools/noir_fontc.py "$SPEC" --out "$TMP/b" >/tmp/noir-tabular-font-build-b.json
cmp "$TMP/a/atlas.r8" "$TMP/b/atlas.r8"
cmp "$TMP/a/manifest.json" "$TMP/b/manifest.json"
cmp "$TMP/a/preview.png" "$TMP/b/preview.png"
cmp "$TMP/a/atlas.png" "$TMP/b/atlas.png"

python3 - "$OUT/manifest.json" examples/log-browser.rkt examples/realtime-monitor.rkt <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
expected = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
assert manifest["schema"] == "noir-font-asset-manifest-v1"
assert manifest["revision"] == 1
assert manifest["face_id"] == "noir-table-body-mono-16"
assert manifest["renderer_kind"] == "atlas-gray"
assert manifest["coverage_policy"] == "tabular-body-v1"
assert manifest["advance_policy"] == "fixed-tabular"
assert manifest["fixed_advance"] == 10.0
assert manifest["glyph_count"] == len(expected) == 37
glyphs = manifest["glyphs"]
assert "".join(glyph["character"] for glyph in glyphs) == expected
assert [glyph["glyph_id"] for glyph in glyphs] == list(range(37))
assert [glyph["codepoint"] for glyph in glyphs] == sorted(glyph["codepoint"] for glyph in glyphs)
assert all(glyph["advance"] == 10.0 for glyph in glyphs)
assert all("source_advance" in glyph for glyph in glyphs)
atlas_path = manifest_path.parent / "atlas.r8"
assert hashlib.sha256(atlas_path.read_bytes()).hexdigest() == manifest["atlas_sha256"]
corpus = "".join(Path(path).read_text(encoding="utf-8") for path in sys.argv[2:])
for literal in ("INFO  TIME  CORE  STARTUP", "ERROR TIME  AUTH  TOKEN DENIED", "WARN ALPHA 042 731 018 012 005", "DEBUG CHARLIE 013 224 009 004 002"):
    assert set(literal) <= set(expected), literal
    assert literal in corpus, literal
print("tabular-body manifest/domain/corpus proof: PASS")
PY

python3 - "$SPEC" "$TMP/closed-domain-attack.json" <<'PY'
import json
import sys
from pathlib import Path
ns = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
ns["extra_text"] = ["!"]
Path(sys.argv[2]).write_text(json.dumps(ns), encoding="utf-8")
PY
set +e
python3 tools/noir_fontc.py "$TMP/closed-domain-attack.json" --out "$TMP/attack" >/tmp/noir-tabular-font-attack.log 2>&1
status=$?
set -e
[[ $status -ne 0 ]]
grep -F 'TABULAR_BODY_V1 is closed' /tmp/noir-tabular-font-attack.log >/dev/null

./tools/verify_fontc_theme.sh >/tmp/noir-tabular-font-static-compat.log 2>&1
echo "tabular body font regression: PASS"
