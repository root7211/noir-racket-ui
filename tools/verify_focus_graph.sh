#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/focus-dashboard.scene.json"
LOG="$ROOT/wgpu-verify/out/focus-dashboard-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:111

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/focus-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

grep -q '"focus_graph":{"entries":\[' "$SCENE"
grep -q '"node":"command-field"' "$SCENE"
grep -q '"node":"query-field"' "$SCENE"
grep -q '"tab_index":5' "$SCENE"
grep -q '"tab_index":20' "$SCENE"

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-focus-xvfb.log 2>&1 &
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
WINDOW_ID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' | head -n1)
[[ -n "$WINDOW_ID" ]]
# XSetInputFocus works without a WM; xdotool's key injection then targets the actual winit window.
DISPLAY="$DISPLAY_NUM" xdotool windowfocus "$WINDOW_ID"
[[ $(DISPLAY="$DISPLAY_NUM" xdotool getwindowfocus) == "$WINDOW_ID" ]]
# slot 0 = command-field (tab-index 5); forward Tab must use compiler next_slot=1.
DISPLAY="$DISPLAY_NUM" xdotool key Tab
sleep 0.30
# Shift+Tab returns using compiler previous_slot=0, not surface/tree order.
DISPLAY="$DISPLAY_NUM" xdotool key shift+Tab
sleep 0.50
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -q 'compiler focus graph: 2 field(s), initial slot=0, fixed Tab ring' "$LOG"
grep -q 'focus-tab forward: slot 0 -> 1 / query-field mask=0x0000000000000001' "$LOG"
grep -q 'focus-tab reverse: slot 1 -> 0 / command-field mask=0x0000000000000002' "$LOG"
grep -q 'tile-select focus-tab: mask=0x0000000000000001' "$LOG"
grep -q 'tile-select focus-tab: mask=0x0000000000000002' "$LOG"
printf 'Noir compiler Focus Graph + real X11 Tab/Shift+Tab verification passed.\n'
