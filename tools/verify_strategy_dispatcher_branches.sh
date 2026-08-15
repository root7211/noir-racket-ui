#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
SOURCE_SCENE="${1:-$ROOT/out/profile-strategy.scene.json}"
FIXTURE_TOOL="$ROOT/tools/make-strategy-dispatch-fixture.js"

run_case() {
  local strategy="$1"
  local display="$2"
  local fixture="$ROOT/out/strategy-${strategy}.scene.json"
  local log="$ROOT/wgpu-verify/out/strategy-${strategy}.log"
  local xvfb_pid=""
  local host_pid=""
  cleanup() {
    [ -n "$host_pid" ] && kill "$host_pid" 2>/dev/null || true
    [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
  }

  node "$FIXTURE_TOOL" "$SOURCE_SCENE" "$fixture" "$strategy"
  Xvfb "$display" -screen 0 800x600x24 >/tmp/noir-strategy-xvfb.log 2>&1 &
  xvfb_pid=$!
  trap cleanup RETURN
  for _ in $(seq 1 30); do
    xdpyinfo -display "$display" >/dev/null 2>&1 && break
    sleep 0.1
  done
  xdpyinfo -display "$display" >/dev/null

  DISPLAY="$display" XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime WGPU_BACKEND=vulkan \
    "$HOST" "$fixture" >"$log" 2>&1 &
  host_pid=$!
  local window_id=""
  for _ in $(seq 1 30); do
    window_id="$(DISPLAY="$display" xdotool search --name 'Noir Glyph Atlas host' 2>/dev/null | head -1 || true)"
    [ -n "$window_id" ] && break
    sleep 0.1
  done
  [ -n "$window_id" ]

  DISPLAY="$display" xdotool mousemove --window "$window_id" 100 250
  sleep 0.1
  DISPLAY="$display" xdotool mousedown 1
  sleep 0.1
  DISPLAY="$display" xdotool mouseup 1
  sleep 0.4

  grep -q "compiler strategy proof: batch=coalesced-activate-refresh-fps-button profile=dispatcher-test-${strategy} strategy=${strategy} metric=gpu_median_ns" "$log"
  grep -q "compiler strategy dispatch: batch=coalesced-activate-refresh-fps-button strategy=${strategy}" "$log"
  grep -q "strategy-executor ${strategy}" "$log"
  grep -q 'glyph-id-patch fps: \[800..804), \[832..836), \[864..868) (12 bytes)' "$log"
  if [ "$strategy" = "packet-aware" ]; then
    grep -q 'tile-redraw selected-mask=0x000000000000003f' "$log"
  fi
  echo "compiler strategy dispatcher branch ${strategy} verified"
  cleanup
  trap - RETURN
}

run_case full-redraw :103
run_case packet-aware :104
