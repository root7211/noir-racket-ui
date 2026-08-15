#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/command-palette.scene.json"
LOG="$ROOT/wgpu-verify/out/command-palette-ascii-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:119
cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/command-palette.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

grep -q '"charset":"ascii-upper"' "$SCENE"
grep -q '"ascii_text_register":{"atlas_page":1,"charset":"ascii-upper","initial_packed":0,"max_chars":6,"reset_packed":0}' "$SCENE"
grep -q '"key":"letter-G"' "$SCENE"
grep -q '"key":"space"' "$SCENE"
! grep -q '"tag":"transaction-button"' "$SCENE"
[[ -x "$HOST" ]]

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-ascii-register-xvfb.log 2>&1 &
XVFB_PID=$!; HOST_PID=""
cleanup() { [[ -n "$HOST_PID" ]] && kill "$HOST_PID" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp "$HOST" "$SCENE" >"$LOG" 2>&1 &
HOST_PID=$!
sleep 2
WINDOW_ID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' | head -n1)
DISPLAY="$DISPLAY_NUM" xdotool windowfocus "$WINDOW_ID"

DISPLAY="$DISPLAY_NUM" xdotool key g p u space BackSpace Return Escape
sleep .5
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -q 'compiler ascii text register: slot=0 field=command-entry chars=6 atlas_page=1 transitions=28' "$LOG"
grep -q 'keyboard-transition ascii-insert: slot=0 field=command-entry.*byte=71' "$LOG"
grep -q 'keyboard-transition ascii-insert: slot=0 field=command-entry.*byte=80' "$LOG"
grep -q 'keyboard-transition ascii-insert: slot=0 field=command-entry.*byte=85' "$LOG"
grep -q 'keyboard-transition ascii-insert: slot=0 field=command-entry.*byte=32' "$LOG"
grep -q 'keyboard-transition ascii-backspace: slot=0 field=command-entry' "$LOG"
grep -q 'keyboard-command Enter: slot=0 field=command-entry kind=commit-pending-register charset=ascii-upper state=command-buffer state_index=0 committed=0->5591111' "$LOG"
grep -q 'keyboard-command Escape: slot=0 field=command-entry charset=ascii-upper' "$LOG"
grep -q 'pending=0x0000000000555047->0x0000000000000000' "$LOG"
printf 'Noir Uppercase ASCII Text Register X11 verification passed.\n'
