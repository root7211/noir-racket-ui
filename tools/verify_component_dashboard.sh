#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/component-dashboard.scene.json"
LOG="$ROOT/wgpu-verify/out/component-dashboard-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:108

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/component-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

# Surface JSON must carry base primitives only; component tags never survive lowering.
if grep -q '"tag":"metric-card"\|"tag":"control-button"' "$SCENE"; then
  echo "component tag leaked into runtime Scene JSON" >&2
  exit 1
fi
grep -q '"id":"fps-card\$label"' "$SCENE"
grep -q '"id":"fps-card\$value"' "$SCENE"
grep -q '"id":"component-refresh-fps"' "$SCENE"

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-component-xvfb.log 2>&1 &
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
DISPLAY="$DISPLAY_NUM" xdotool mousemove 105 245 click 1
sleep 0.25
DISPLAY="$DISPLAY_NUM" xdotool mousemove 300 245 click 1
sleep 0.25
DISPLAY="$DISPLAY_NUM" xdotool mousemove 500 245 click 1
sleep 0.75
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -q 'coalesced-activate-component-refresh-fps' "$LOG"
grep -q 'glyph-id-patch fps-card\$value:' "$LOG"
grep -q 'coalesced-activate-component-refresh-latency' "$LOG"
grep -q 'glyph-id-patch latency-card\$value:' "$LOG"
grep -q 'coalesced-activate-component-advance-progress' "$LOG"
grep -q 'instance-patch progress: \[448..452)' "$LOG"
printf 'Noir component macro inline + real X11/wgpu verification passed.\n'
