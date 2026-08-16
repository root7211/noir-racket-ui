#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/log-browser.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
LOG=/tmp/noir-log-browser-regression.log
BASE_DISPLAY=$((300 + ($$ % 40) * 2))
TAMPER_DISPLAY=:$BASE_DISPLAY
DISPLAY_NUM=:$((BASE_DISPLAY + 1))
PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  for pid in "${PIDS[@]:-}"; do
    [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true
  done
  rm -f "$ROOT/out/noir-log-browser-tampered.scene.json"
}
trap cleanup EXIT INT TERM

start_xvfb() {
  local display=$1
  local log=$2
  local number=${display#:}
  [[ ! -e "/tmp/.X${number}-lock" ]] || { echo "display $display is already in use" >&2; return 1; }
  Xvfb "$display" -screen 0 1280x720x24 >"$log" 2>&1 &
  LAST_XVFB_PID=$!
  PIDS+=("$LAST_XVFB_PID")
  sleep 1
  kill -0 "$LAST_XVFB_PID"
}

stop_pid() {
  local pid=$1
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

if [[ ! -x "$BIN" ]]; then
  echo "missing release host: $BIN" >&2
  exit 2
fi

cd "$ROOT"
NOIR_ENTRY_MODULE=examples/log-browser.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-log-browser-regression-export.log 2>&1

grep -F '"log_browser_plan"' "$SCENE" >/dev/null
grep -F '"system-log-browser"' "$SCENE" >/dev/null

tampered="$ROOT/out/noir-log-browser-tampered.scene.json"
sed '0,/noir-log-browser-plan-v1/s//noir-log-browser-plan-v9/' "$SCENE" >"$tampered"
start_xvfb "$TAMPER_DISPLAY" /tmp/noir-log-browser-tampered-xvfb.log
tamper_xvfb=$LAST_XVFB_PID
set +e
DISPLAY="$TAMPER_DISPLAY" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  "$BIN" "$tampered" >/tmp/noir-log-browser-tampered.log 2>&1
tamper_status=$?
set -e
stop_pid "$tamper_xvfb"
[[ $tamper_status -ne 0 ]]
grep -F 'unsupported log_browser_plan ABI' /tmp/noir-log-browser-tampered.log >/dev/null

start_xvfb "$DISPLAY_NUM" /tmp/noir-log-browser-regression-xvfb.log
positive_xvfb=$LAST_XVFB_PID
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  "$BIN" --inject-log-append system-log-browser "$SCENE" >"$LOG" 2>&1 &
HOST=$!
PIDS+=("$HOST")
sleep 4
kill -0 "$HOST"

WID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' 2>/dev/null | head -n1)
[[ -n "$WID" ]]
DISPLAY="$DISPLAY_NUM" xdotool windowfocus --sync "$WID"
[[ "$(DISPLAY="$DISPLAY_NUM" xdotool getwindowfocus)" == "$WID" ]]
DISPLAY="$DISPLAY_NUM" xdotool key --clearmodifiers End
sleep 2
# Compiler log records the list scissor at y=146; row 9998 is the second 28px row.
DISPLAY="$DISPLAY_NUM" xdotool mousemove --sync 120 186 click 1
sleep 1
DISPLAY="$DISPLAY_NUM" xdotool key --clearmodifiers Return
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
# The visible tail keeps three rows in the four-slot ring and emits fixed compact subranges.
grep -F 'compact-register scroll: list=system-log table=system-log-data capacity=10000 target=9997 row-tiles=[1, 2, 3] physical-slots=4' "$LOG"
grep -F 'glyph-direct-draw tile=0 packet=2 page=0 placements=[171..200) lanes=29 reason=no-vertex-subgroup-compatible-direct' "$LOG"

echo "log browser regression: PASS"
