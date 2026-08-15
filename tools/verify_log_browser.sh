#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/log-browser.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
LOG=/tmp/noir-log-browser-regression.log
DISPLAY_NUM=:117

if [[ ! -x "$BIN" ]]; then
  echo "missing release host: $BIN" >&2
  exit 2
fi

cd "$ROOT"
NOIR_ENTRY_MODULE=examples/log-browser.rkt PLTCOLLECTS="$ROOT:" racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-log-browser-regression-export.log 2>&1

grep -F '"log_browser_plan"' "$SCENE" >/dev/null
grep -F '"system-log-browser"' "$SCENE" >/dev/null

tampered=/tmp/noir-log-browser-tampered.scene.json
sed '0,/noir-log-browser-plan-v1/s//noir-log-browser-plan-v9/' "$SCENE" >"$tampered"
set +e
DISPLAY=:118 Xvfb :118 -screen 0 1280x720x24 >/tmp/noir-log-browser-tampered-xvfb.log 2>&1 &
TAMPER_XVFB=$!
sleep 1
DISPLAY=:118 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" "$tampered" >/tmp/noir-log-browser-tampered.log 2>&1
TAMPER_STATUS=$?
kill "$TAMPER_XVFB" 2>/dev/null || true
set -e
[[ $TAMPER_STATUS -ne 0 ]]
grep -F 'unsupported log_browser_plan ABI' /tmp/noir-log-browser-tampered.log >/dev/null

Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 >/tmp/noir-log-browser-regression-xvfb.log 2>&1 &
XVFB=$!
HOST=""
cleanup() {
  [[ -n "$HOST" ]] && kill "$HOST" 2>/dev/null || true
  kill "$XVFB" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" --inject-log-append system-log-browser "$SCENE" >"$LOG" 2>&1 &
HOST=$!
sleep 4
WID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' 2>/dev/null | head -n1)
[[ -n "$WID" ]]
DISPLAY="$DISPLAY_NUM" xdotool windowfocus --sync "$WID"
DISPLAY="$DISPLAY_NUM" xdotool key End
sleep 1
# Compiler log records the list scissor at y=146; row 9998 is the second 28px row.
DISPLAY="$DISPLAY_NUM" xdotool mousemove --sync 120 186 click 1
sleep 1
DISPLAY="$DISPLAY_NUM" xdotool key Return
sleep 3

# Startup and strict plan admission.
grep -F 'compiler log browser: id=system-log-browser' "$LOG"
# Tail records are offscreen at viewport zero: CPU arena changes, zero glyph writes.
grep -F 'data-update-batch: list=system-log updates=3 visible=0 arena-only=3 gpu-glyph-writes=0 render-request=false' "$LOG"
grep -F 'log-browser append: id=system-log-browser batch=system-log-browser-append records=3 tail=9997..9999 source=compiler-artifact' "$LOG"
# Real End, real ERROR row release, and real Enter all use compiler-proved paths.
grep -F 'list-navigation-plan: id=log-navigation key=End list=system-log from=0 to=9997' "$LOG"
grep -F 'list-selection: list=system-log logical=9998 physical=2' "$LOG"
grep -F 'log-browser detail: id=system-log-browser logical=9998 level=ERROR glyph-writes=29' "$LOG"
grep -F 'row-activation: list=system-log logical=9998 physical=2 action-slot=0 batch=coalesced-activate-append-tail' "$LOG"
grep -F 'coalesced-batch execute: coalesced-activate-append-tail' "$LOG"
grep -F 'packet-activity-skip worklist=no-packets index=2 packets=[] reason=compiler-empty' "$LOG"
# The visible tail keeps three rows in the four-slot ring and only emits compact subranges.
grep -F 'compact-register scroll: list=system-log table=system-log-data capacity=10000 target=9997 row-tiles=[1, 2, 3] physical-slots=4' "$LOG"
grep -F 'packet-direct-subrange tile=0 packet=2 page=0 placements=[143..172) lanes=29 reason=no-packets-direct' "$LOG"

echo "log browser regression: PASS"
