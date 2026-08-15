#!/usr/bin/env bash
# Real X11/wgpu oracle for compiler-fixed State-to-Packet Worklist lowering.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/command-palette.scene.json"
LOG="$ROOT/wgpu-verify/out/command-palette-packet-worklist-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:123
cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/command-palette.rkt" racket tools/export-dashboard.rkt "$SCENE"
grep -q '"id":"all-packets"' "$SCENE"
grep -q '"id":"dynamic-packets"' "$SCENE"
grep -q '"id":"no-packets"' "$SCENE"
grep -q '"id":"field-command-entry"' "$SCENE"
grep -q '"packet_indices":\[2\]' "$SCENE"
rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-packet-worklist-xvfb.log 2>&1 &
XVFB_PID=$!; HOST_PID=""
cleanup() { [[ -n "$HOST_PID" ]] && kill "$HOST_PID" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp stdbuf -oL "$HOST" "$SCENE" >"$LOG" 2>&1 & HOST_PID=$!
sleep 2
WINDOW_ID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' | head -n1)
DISPLAY="$DISPLAY_NUM" xdotool windowfocus "$WINDOW_ID"
DISPLAY="$DISPLAY_NUM" xdotool key g p u Return
sleep .5
kill "$HOST_PID" 2>/dev/null || true; wait "$HOST_PID" 2>/dev/null || true; HOST_PID=""
grep -q 'packet-activity-dispatch worklist=all-packets index=0 packets=\[0, 1, 2, 3\] workgroups=4 workgroup_size=32 output=activity+indirect' "$LOG"
grep -q 'compiler packet worklists: all-packets#0=\[0, 1, 2, 3\]; dynamic-packets#1=\[2\]; no-packets#2=\[\]; field-command-entry#3=\[2\]' "$LOG"
grep -q 'packet-activity-dispatch worklist=field-command-entry index=3 packets=\[2\] workgroups=1 workgroup_size=32 output=activity+indirect' "$LOG"
grep -q 'packet-indirect-draw tile=1 packet=2 page=1 activity_word=2 indirect_offset=32 lanes=6 dynamic=true' "$LOG"
grep -q 'command-matcher Enter: slot=0 field=command-entry packed=0x0000000000555047 length=3 action=gpu-command action_index=0' "$LOG"
printf 'Noir State-to-Packet Worklist X11/wgpu verification passed.\n'
