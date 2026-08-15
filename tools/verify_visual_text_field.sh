#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/visual-focus-dashboard.scene.json"
LOG="$ROOT/wgpu-verify/out/visual-focus-dashboard-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:114
cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/focus-dashboard.rkt" racket tools/export-dashboard.rkt "$SCENE"
grep -q '"text_field_visuals":\[' "$SCENE"
grep -q '"blink_track"' "$SCENE"
grep -q '"glyph_id_offsets":\[896,928,960\]' "$SCENE"
grep -q '"glyph_id_offsets":\[640,672,704\]' "$SCENE"
rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-visual-text-xvfb.log 2>&1 &
XVFB_PID=$!
HOST_PID=""
cleanup() { [[ -n "$HOST_PID" ]] && kill "$HOST_PID" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp "$HOST" "$SCENE" >"$LOG" 2>&1 &
HOST_PID=$!
sleep 2
WINDOW_ID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' | head -n1)
DISPLAY="$DISPLAY_NUM" xdotool windowfocus "$WINDOW_ID"
DISPLAY="$DISPLAY_NUM" xdotool key 7
sleep .2
DISPLAY="$DISPLAY_NUM" xdotool key Tab
sleep .2
DISPLAY="$DISPLAY_NUM" xdotool key 4
sleep .2
DISPLAY="$DISPLAY_NUM" xdotool key BackSpace
sleep .5
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""
grep -q 'compiler text field visuals: 2 caret/placeholder/focus plan(s)' "$LOG"
grep -q 'compiler text field visual: slot=0 node=command-field blink=500ms track=command-field-caret-blink' "$LOG"
grep -q 'keyboard-transition insert: slot=0 field=command-field key=digit-7 cursor=0->1 glyph-id-patch \[896..900) glyph_id=7' "$LOG"
grep -q 'focus-tab forward: slot 0 -> 1 / query-field' "$LOG"
grep -q 'keyboard-transition insert: slot=1 field=query-field key=digit-4 cursor=0->1 glyph-id-patch \[640..644) glyph_id=4' "$LOG"
grep -q 'keyboard-transition backspace: slot=1 field=query-field cursor=1->0 glyph-id-patch \[640..644) glyph_id=0' "$LOG"
grep -q 'text-field-visual sync: slot=0 cursor=0 caret_ndc_x=-0.88125 focus_alpha=0.30 placeholder_alpha=0.45' "$LOG"
grep -q 'text-field-visual sync: slot=0 cursor=1 caret_ndc_x=-0.63125 focus_alpha=0.30 placeholder_alpha=0' "$LOG"
grep -q 'text-field-visual sync: slot=1 cursor=0 caret_ndc_x=-0.88125 focus_alpha=0.30 placeholder_alpha=0.45' "$LOG"
grep -q 'caret-blink track: phase=' "$LOG"
grep -q 'tile-glyph-draw tile=0 packet=1 page=1 placements=\[15..20) count=5 dynamic=false' "$LOG"
grep -q 'tile-glyph-draw tile=0 packet=2 page=0 placements=\[20..23) count=3 dynamic=true' "$LOG"
printf 'Noir compiler Caret/Placeholder/Focus visual X11 verification passed.\n'
