#!/usr/bin/env bash
# Real wgpu/X11 verification for GPU-driven packet activity -> indirect draw ABI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/command-palette.scene.json"
LOG="$ROOT/wgpu-verify/out/command-palette-gpu-packet-activity-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:122
cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/command-palette.rkt" racket tools/export-dashboard.rkt "$SCENE"
grep -q '"activity_word_offset":0' "$SCENE"
grep -q '"indirect_byte_offset":48' "$SCENE"
rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-gpu-packet-activity-xvfb.log 2>&1 &
XVFB_PID=$!; HOST_PID=""
cleanup() { [[ -n "$HOST_PID" ]] && kill "$HOST_PID" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp "$HOST" "$SCENE" >"$LOG" 2>&1 & HOST_PID=$!
sleep 2
WINDOW_ID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' | head -n1)
DISPLAY="$DISPLAY_NUM" xdotool windowfocus "$WINDOW_ID"
DISPLAY="$DISPLAY_NUM" xdotool key g p u Return
sleep .5
kill "$HOST_PID" 2>/dev/null || true; wait "$HOST_PID" 2>/dev/null || true; HOST_PID=""
grep -q 'compiler packet activity: gpu-driven-indirect=true variant=Scalar adapter-subgroup=true wgsl-subgroup=false fixed activity-word/indirect-command ABI' "$LOG"
grep -q 'packet-activity-differential: selected=Scalar reference=Scalar packets=4 activity+indirect=equal' "$LOG"
grep -q 'packet-activity-dispatch packets=4 workgroup_size=32 output=activity+indirect' "$LOG"
grep -q 'packet-indirect-draw full packet=2 activity_word=2 indirect_offset=32 lanes=6 dynamic=true' "$LOG"
grep -q 'packet-indirect-draw tile=1 packet=2 page=1 activity_word=2 indirect_offset=32 lanes=6 dynamic=true' "$LOG"
grep -q 'keyboard-transition ascii-insert: slot=0 field=command-entry' "$LOG"
grep -q 'command-matcher Enter: slot=0 field=command-entry packed=0x0000000000555047 length=3 action=gpu-command action_index=0' "$LOG"
printf 'Noir GPU-driven Packet Activity -> Indirect Draw X11/wgpu verification passed.\n'
