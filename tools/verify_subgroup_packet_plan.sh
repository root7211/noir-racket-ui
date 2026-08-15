#!/usr/bin/env bash
# Real X11/wgpu verification for compiler-emitted width-32 Glyph Placement Subgroup Packet Plan.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/command-palette.scene.json"
LOG="$ROOT/wgpu-verify/out/command-palette-subgroup-packet-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:121
cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/command-palette.rkt" racket tools/export-dashboard.rkt "$SCENE"
grep -q '"subgroup_packet_plan":\[' "$SCENE"
grep -q '"subgroup_width":32' "$SCENE"
grep -q '"active_lane_mask"' "$SCENE"
rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-subgroup-packet-xvfb.log 2>&1 &
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
grep -q 'compiler subgroup packets: .*width-32 packet(s), vertex-subgroup-supported=' "$LOG"
grep -q 'subgroup-packet-draw full packet=' "$LOG"
grep -q 'subgroup-packet-draw tile=.*lanes=.*active_mask=' "$LOG"
grep -q 'keyboard-transition ascii-insert: slot=0 field=command-entry' "$LOG"
grep -q 'command-matcher Enter: slot=0 field=command-entry packed=0x0000000000555047 length=3 action=gpu-command action_index=0' "$LOG"
printf 'Noir Subgroup Packet Plan X11/wgpu verification passed.\n'
