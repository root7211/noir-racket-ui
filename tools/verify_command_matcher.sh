#!/usr/bin/env bash
# 真实 X11/wgpu oracle：验证 compiler packed-command matcher，而非直接调用 Host 方法。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/command-palette.scene.json"
LOG="$ROOT/wgpu-verify/out/command-palette-command-matcher-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:120

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/command-palette.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

grep -q '"command_matchers":\[{"action":"gpu-command","action_index":0,"field":"command-entry","focus_slot":0,"length":3,"literal":"GPU","packed":5591111,"tile_ids":\[0,1\]' "$SCENE"
grep -q '"charset":"ascii-upper"' "$SCENE"
[[ -x "$HOST" ]]

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-command-matcher-xvfb.log 2>&1 &
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
DISPLAY="$DISPLAY_NUM" xdotool windowfocus "$WINDOW_ID"

# GPU must match: compiler dispatches Action Slot 0. Escape then resets the pending text.
DISPLAY="$DISPLAY_NUM" xdotool key g p u Return
sleep .3
DISPLAY="$DISPLAY_NUM" xdotool key Escape
sleep .2
# X has no compiler matcher entry. Enter is a fixed reject with zero state/GPU business writes.
DISPLAY="$DISPLAY_NUM" xdotool key x Return
sleep .3
DISPLAY="$DISPLAY_NUM" xdotool key Escape
sleep .4
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -q 'compiler command matcher: slot=0 field=command-entry literal=GPU length=3 packed=0x0000000000555047 action=gpu-command action_index=0 mask=0x0000000000000003' "$LOG"
grep -q 'command-matcher Enter: slot=0 field=command-entry packed=0x0000000000555047 length=3 action=gpu-command action_index=0 winner_writes=1 mask=0x0000000000000003' "$LOG"
grep -q 'state-slot write: action=gpu-command state=command-applied index=0 op=add value=1' "$LOG"
grep -q 'command-matcher Enter rejected: slot=0 field=command-entry packed=0x0000000000000058 length=1 state_writes=0 gpu_writes=0' "$LOG"
grep -q 'keyboard-command Escape: slot=0 field=command-entry charset=ascii-upper' "$LOG"
printf 'Noir fixed Command Matcher X11 verification passed.\n'
