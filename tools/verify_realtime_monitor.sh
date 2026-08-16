#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/realtime-monitor.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN=/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin
LOG=/tmp/noir-realtime-monitor-regression.log
BASE_DISPLAY=$((360 + ($$ % 40) * 2))
TAMPER_DISPLAY=:$BASE_DISPLAY
POSITIVE_DISPLAY=:$((BASE_DISPLAY + 1))
ARENA_DISPLAY=:$((BASE_DISPLAY + 2))
PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true; done
  rm -f "$ROOT/out/realtime-monitor-tampered.scene.json"
}
trap cleanup EXIT INT TERM

start_xvfb() {
  local display=$1 log=$2 number=${1#:}
  [[ ! -e "/tmp/.X${number}-lock" ]] || { echo "display $display is already in use" >&2; return 1; }
  Xvfb "$display" -screen 0 1280x720x24 >"$log" 2>&1 &
  LAST_XVFB_PID=$!
  PIDS+=("$LAST_XVFB_PID")
  sleep 1
  kill -0 "$LAST_XVFB_PID"
}

stop_pid() {
  kill "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-monitor-racket-tests.log 2>&1
NOIR_ENTRY_MODULE=examples/realtime-monitor.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-monitor-export.log 2>&1

grep -F '"logical_capacity":10000' "$SCENE" >/dev/null
grep -F '"id":"telemetry-grid"' "$SCENE" >/dev/null
grep -F '"font_placement_plan":{"revision":1,"schema":"noir-font-placement-plan-v1"}' "$SCENE" >/dev/null
grep -F '"dynamic":true' "$SCENE" >/dev/null

PATH="$TOOLCHAIN:$PATH" RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30 CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30 \
  "$TOOLCHAIN/cargo" build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host \
  >/tmp/noir-monitor-build.log 2>&1

# A declared bootstrap row containing an illegal lower-case glyph must be rejected before first frame.
tampered="$ROOT/out/realtime-monitor-tampered.scene.json"
python3 "$ROOT/tools/mutate_realtime_monitor_scene.py" lowercase "$SCENE" "$tampered"
start_xvfb "$TAMPER_DISPLAY" /tmp/noir-monitor-tampered-xvfb.log
tamper_xvfb=$LAST_XVFB_PID
set +e
DISPLAY="$TAMPER_DISPLAY" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" "$tampered" >/tmp/noir-monitor-tampered.log 2>&1
tamper_status=$?
set -e
stop_pid "$tamper_xvfb"
[[ $tamper_status -ne 0 ]]
grep -F 'violates fixed legacy glyph domain/width proof' /tmp/noir-monitor-tampered.log >/dev/null

start_xvfb "$POSITIVE_DISPLAY" /tmp/noir-monitor-positive-xvfb.log
DISPLAY="$POSITIVE_DISPLAY" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" \
  --inject-log-append telemetry-dashboard \
  --data-update-batch telemetry-grid '0=WARN ALPHA 099 900 090 020 010,7000=DEBUG ZULU 013 222 009 004 002' \
  "$SCENE" >"$LOG" 2>&1 &
HOST=$!
PIDS+=("$HOST")
sleep 5
kill -0 "$HOST"

CAPTURE="$ROOT/out/realtime-monitor-ui.png"
ffmpeg -hide_banner -loglevel error -y -f x11grab -video_size 1280x720 \
  -i "$POSITIVE_DISPLAY.0+0,0" -frames:v 1 "$CAPTURE"
test -s "$CAPTURE"

WID=$(DISPLAY="$POSITIVE_DISPLAY" xdotool search --name 'Noir Glyph Atlas host' 2>/dev/null | head -n1)
[[ -n "$WID" ]]
DISPLAY="$POSITIVE_DISPLAY" xdotool windowfocus --sync "$WID"
[[ "$(DISPLAY="$POSITIVE_DISPLAY" xdotool getwindowfocus)" == "$WID" ]]
DISPLAY="$POSITIVE_DISPLAY" xdotool key --clearmodifiers End
sleep 2
DISPLAY="$POSITIVE_DISPLAY" xdotool mousemove --sync 120 186 click 1
sleep 1
DISPLAY="$POSITIVE_DISPLAY" xdotool key --clearmodifiers Return
sleep 3

grep -F 'compiler log browser: id=telemetry-dashboard list=telemetry-grid' "$LOG"
grep -F 'compiler font placement proof: active-page2-glyphs=71 registered-font-assets=1 mode=static-proportional-v1' "$LOG"
grep -F 'data-update-batch: list=telemetry-grid updates=3 visible=2 arena-only=1 gpu-glyph-writes=72 render-request=true' "$LOG"
grep -F 'data-update-batch: list=telemetry-grid updates=2 visible=1 arena-only=1 gpu-glyph-writes=36 render-request=true' "$LOG"
grep -F 'log-browser append: id=telemetry-dashboard batch=telemetry-dashboard-append records=3 tail=9997..9999 source=compiler-artifact' "$LOG"
grep -F 'list-navigation-plan: id=monitor-navigation key=End list=telemetry-grid from=0 to=9997' "$LOG"
grep -F 'list-selection: list=telemetry-grid logical=9998 physical=2' "$LOG"
grep -F 'log-browser detail: id=telemetry-dashboard logical=9998 level=ERROR glyph-writes=29' "$LOG"
grep -F 'row-activation: list=telemetry-grid logical=9998 physical=2 action-slot=0 batch=coalesced-activate-refresh-telemetry' "$LOG"
grep -F 'coalesced-batch execute: coalesced-activate-refresh-telemetry' "$LOG"

# Purely offscreen refresh: the fixed data arena changes, but no glyph storage write
# or render request is admitted because logical row 7000 is outside viewport 0..2.
start_xvfb "$ARENA_DISPLAY" /tmp/noir-monitor-arena-only-xvfb.log
arena_xvfb=$LAST_XVFB_PID
DISPLAY="$ARENA_DISPLAY" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" \
  --data-update-batch telemetry-grid '7000=DEBUG ZULU 013 222 009 004 002' \
  "$SCENE" >/tmp/noir-monitor-arena-only.log 2>&1 &
arena_host=$!
PIDS+=("$arena_host")
sleep 4
kill -0 "$arena_host"
grep -F 'data-update-batch: list=telemetry-grid updates=1 visible=0 arena-only=1 gpu-glyph-writes=0 render-request=false' /tmp/noir-monitor-arena-only.log
stop_pid "$arena_host"
stop_pid "$arena_xvfb"

echo "realtime monitor regression: PASS"
