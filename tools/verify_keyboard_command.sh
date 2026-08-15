#!/usr/bin/env bash
# 真实 X11/wgpu 端到端 oracle：固定 command table，而非模拟 Host 方法调用。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/command-dashboard.scene.json"
LOG="$ROOT/wgpu-verify/out/command-dashboard-keyboard-command-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:115

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/command-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

grep -q '"keyboard_command_map"' "$SCENE"
grep -q '"action":"apply-command","action_index":0,"focus_slot":0,"key":"enter","kind":"action","target_state":null,"target_state_index":null,"tile_ids":\[0,2\]' "$SCENE"
grep -q '"action":null,"action_index":null,"focus_slot":0,"key":"escape","kind":"reset","target_state":null,"target_state_index":null,"tile_ids":\[0\]' "$SCENE"
grep -q '"action":null,"action_index":null,"focus_slot":1,"key":"escape","kind":"reset","target_state":null,"target_state_index":null,"tile_ids":\[1\]' "$SCENE"
[[ -x "$HOST" ]]

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-keyboard-command-xvfb.log 2>&1 &
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

# initial focus slot is command-field: digit 5, Enter applies submitted += 1 through the
# fixed action plan; digit 3 then Escape clears all three command glyph ID cells.
DISPLAY="$DISPLAY_NUM" xdotool key 5
sleep .2
DISPLAY="$DISPLAY_NUM" xdotool key Return
sleep .3
DISPLAY="$DISPLAY_NUM" xdotool key 3
sleep .2
DISPLAY="$DISPLAY_NUM" xdotool key Escape
sleep .5

kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

# Startup proof: two focus slots; command-field gets Enter+Escape and query-field only Escape.
grep -q 'compiler keyboard command: slot=0 Enter -> apply-command mask=0x0000000000000005' "$LOG"
grep -q 'compiler keyboard command: slot=0 Escape -> reset mask=0x0000000000000001' "$LOG"
grep -q 'compiler keyboard command: slot=1 Escape -> reset mask=0x0000000000000002' "$LOG"
# Runtime oracle: real X11 key events hit only precomputed paths and do not invoke layout/shaping.
grep -q 'keyboard-transition insert: slot=0 field=command-field key=digit-5 cursor=0->1 glyph-id-patch \[544..548) glyph_id=5' "$LOG"
grep -q 'event-map dispatch: apply-command' "$LOG"
grep -q 'event-map dispatch: apply-command' "$LOG"
grep -q 'state-slot write: action=apply-command state=submitted index=2 op=add value=3' "$LOG"
grep -q 'instance-patch apply-progress state=submitted state_index=2: \[536..540) size.x=0.337500' "$LOG"
grep -q 'keyboard-command Enter: slot=0 field=command-field action=apply-command action_index=0 winner_writes=1 mask=0x0000000000000005' "$LOG"
grep -q 'keyboard-transition insert: slot=0 field=command-field key=digit-3 cursor=1->2 glyph-id-patch \[576..580) glyph_id=3' "$LOG"
grep -q 'keyboard-command Escape: slot=0 field=command-field charset=digits reset_glyph_offsets=\[544, 576, 608\] mask=0x0000000000000001' "$LOG"
grep -q 'tile-select keyboard-command: mask=0x0000000000000001' "$LOG"

printf 'Noir compiler Keyboard Command Map X11 verification passed.\n'
