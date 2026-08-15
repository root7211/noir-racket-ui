#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/log-browser.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN=/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin
LOG=/tmp/noir-font-placement-regression.log
BASE_DISPLAY=$((180 + ($$ % 20) * 3))
FACE_DISPLAY=:$BASE_DISPLAY
UV_DISPLAY=:$((BASE_DISPLAY + 1))
POSITIVE_DISPLAY=:$((BASE_DISPLAY + 2))
PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  for pid in "${PIDS[@]:-}"; do
    [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true
  done
  rm -f "$ROOT/out/noir-font-placement-face-tampered.scene.json" \
        "$ROOT/out/noir-font-placement-uv-tampered.scene.json"
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

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-font-placement-racket-tests.log 2>&1
NOIR_ENTRY_MODULE=examples/log-browser.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-font-placement-export.log 2>&1

grep -F '"font_placement_plan":{"revision":1,"schema":"noir-font-placement-plan-v1"}' "$SCENE" >/dev/null
grep -F '"face_id":"noir-desktop-sans-18"' "$SCENE" >/dev/null
grep -F '"atlas_page":2' "$SCENE" >/dev/null

PATH="$TOOLCHAIN:$PATH" RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30 CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30 \
  "$TOOLCHAIN/cargo" build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host \
  >/tmp/noir-font-placement-build.log 2>&1

for spec in "face:$FACE_DISPLAY" "uv:$UV_DISPLAY"; do
  kind=${spec%%:*}
  display=:${spec##*:}
  tampered="$ROOT/out/noir-font-placement-${kind}-tampered.scene.json"
  python3 "$ROOT/tools/mutate_font_placement_scene.py" "$kind" "$SCENE" "$tampered"
  start_xvfb "$display" "/tmp/noir-font-placement-${kind}-tampered-xvfb.log"
  tamper_xvfb=$LAST_XVFB_PID
  set +e
  DISPLAY="$display" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
    "$BIN" "$tampered" >"/tmp/noir-font-placement-${kind}-tampered.log" 2>&1
  status=$?
  set -e
  stop_pid "$tamper_xvfb"
  [[ $status -ne 0 ]]
  if [[ "$kind" == face ]]; then
    grep -F 'references unregistered face tampered-font-face' "/tmp/noir-font-placement-${kind}-tampered.log" >/dev/null
  else
    grep -F 'UV does not match face noir-desktop-sans-18 manifest glyph' "/tmp/noir-font-placement-${kind}-tampered.log" >/dev/null
  fi
done

start_xvfb "$POSITIVE_DISPLAY" /tmp/noir-font-placement-regression-xvfb.log
positive_xvfb=$LAST_XVFB_PID
DISPLAY="$POSITIVE_DISPLAY" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  "$BIN" "$SCENE" >"$LOG" 2>&1 &
HOST=$!
PIDS+=("$HOST")
sleep 4
kill -0 "$HOST"

grep -F 'compiler font placement proof: active-page2-glyphs=60 registered-font-assets=1 mode=static-proportional-v1' "$LOG"
grep -F 'font-atlas-upload: face=noir-desktop-sans-18 page=2 bytes=262144' "$LOG"
grep -F 'glyph-direct-draw full packet=0 page=2 placements=[32..43) lanes=11 reason=page2-static-v1' "$LOG"
grep -F 'glyph-direct-draw full packet=1 page=1 placements=[43..75) lanes=32 reason=no-vertex-subgroup-compatible-direct' "$LOG"

CAPTURE="$ROOT/out/log-browser-ui/15-fontc-page2-compatible-full.png"
ffmpeg -hide_banner -loglevel error -y -f x11grab -video_size 1280x720 \
  -i "$POSITIVE_DISPLAY.0+0,0" -frames:v 1 "$CAPTURE"
test -s "$CAPTURE"

echo "font placement scene regression: PASS"
