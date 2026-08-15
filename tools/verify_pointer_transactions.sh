#!/usr/bin/env bash
# 真实 X11/wgpu pointer transaction 验证：transaction-button 已在 Racket 宏展开为普通 button + 固定 Event transaction index。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/settings-dashboard.scene.json"
LOG="$ROOT/wgpu-verify/out/settings-dashboard-pointer-transaction-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:118

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/settings-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

# compiler-only transaction button ABI: no form runtime tag, two event entries, same static transaction index.
! grep -q '"tag":"transaction-button"' "$SCENE"
grep -q '"node":"apply-all-button"' "$SCENE"
grep -q '"node":"reset-all-button"' "$SCENE"
grep -q '"node":"apply-all-button"[^}]*"transaction_index":0,"transaction_op":"commit"' "$SCENE"
grep -q '"node":"reset-all-button"[^}]*"transaction_index":0,"transaction_op":"reset"' "$SCENE"
grep -q '"kind":"transaction"' "$SCENE"
[[ -x "$HOST" ]]

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-pointer-transaction-xvfb.log 2>&1 &
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

# slot 0: 5 -> Escape -> 720. slot 1: 72 -> 729 (second 9 rejected). slot 2: 16 -> 164.
DISPLAY="$DISPLAY_NUM" xdotool key Escape
DISPLAY="$DISPLAY_NUM" xdotool key 7
DISPLAY="$DISPLAY_NUM" xdotool key 2
DISPLAY="$DISPLAY_NUM" xdotool key 0
DISPLAY="$DISPLAY_NUM" xdotool key Tab
DISPLAY="$DISPLAY_NUM" xdotool key 9
DISPLAY="$DISPLAY_NUM" xdotool key 9
DISPLAY="$DISPLAY_NUM" xdotool key Tab
DISPLAY="$DISPLAY_NUM" xdotool key 4
sleep .4

# Static button rects are apply x=[46,226), reset x=[320,500), y=[344,356). Real pointer activate performs transaction index 0.
DISPLAY="$DISPLAY_NUM" xdotool mousemove --window "$WINDOW_ID" 136 350 click 1
sleep .4
# Current focus remains slot 2; mutate pending only, then pointer reset must not write State Slots.
DISPLAY="$DISPLAY_NUM" xdotool key 5
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool mousemove --window "$WINDOW_ID" 410 350 click 1
sleep .4

kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

# startup and strict pointer execution oracle.
grep -q 'compiler transaction button: node=apply-all-button operation=commit transaction=apply-all index=0' "$LOG"
grep -q 'compiler transaction button: node=reset-all-button operation=reset transaction=apply-all index=0' "$LOG"
grep -q 'coalesced-batch transaction-ref: index=0 deferred-to-pointer-dispatch' "$LOG"
grep -q 'pointer-transaction: node=apply-all-button operation=commit id=apply-all index=0 atomic=true commits=\[field_slot=0:state_index=2:5->720, field_slot=1:state_index=0:72->729, field_slot=2:state_index=1:16->164\] mask=0x0000000000000007' "$LOG"
grep -q 'pointer-transaction: node=reset-all-button operation=reset id=apply-all index=0 state_writes=0 resets=\[field_slot=0:720->0, field_slot=1:729->0, field_slot=2:164->0\] mask=0x0000000000000007' "$LOG"
grep -q 'tile-select pointer-transaction: mask=0x0000000000000007' "$LOG"

printf 'Noir pointer-triggered apply-all/reset-all transaction X11 verification passed.\n'
