#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/repeat-dashboard.scene.json"
LOG="$ROOT/wgpu-verify/out/repeat-dashboard-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:110

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/repeat-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

if grep -q '"tag":"repeat/ui"' "$SCENE"; then
  echo "repeat/ui tag leaked into runtime Scene JSON" >&2
  exit 1
fi
for id in core-0 core-1 core-2 core-3; do
  grep -q "\"id\":\"${id}\$label\"" "$SCENE"
  grep -q "\"id\":\"${id}\$value\"" "$SCENE"
done
grep -q '"glyph_capacity":59' "$SCENE"

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-repeat-xvfb.log 2>&1 &
XVFB_PID=$!
HOST_PID=""
cleanup() {
  [[ -n "$HOST_PID" ]] && kill "$HOST_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp "$HOST" "$SCENE" >"$LOG" 2>&1 &
HOST_PID=$!
sleep 2
# Event Map fixes the sole control-button to x=46..226, y=198..244.
DISPLAY="$DISPLAY_NUM" xdotool mousemove 120 220 click 1
sleep 0.75
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -q 'coalesced-activate-refresh-core0-button' "$LOG"
grep -q 'glyph-id-patch core-0\$value: \[928..932), \[960..964), \[992..996) (12 bytes)' "$LOG"
printf 'Noir repeat/ui static expansion + real X11/wgpu verification passed.\n'
