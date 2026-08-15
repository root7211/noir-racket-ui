#!/usr/bin/env bash
# End-to-end X11 scroll-to-end benchmark. It measures input injection through
# framework-visible viewport completion only; it is not a GPU frame/present metric.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLES="${1:-15}"
OUT="$ROOT/wgpu-verify/out/noir-gpui-virtual-list-scroll-samples.jsonl"
NOIR_BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
NOIR_SCENE="$ROOT/out/virtual-list-dashboard.scene.json"
GPUI_BIN="$ROOT/gpui-virtual-list-benchmark/target/release/gpui-virtual-list-benchmark"
DISPLAY_NUM=:87
: >"$OUT"

Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 >/tmp/noir-gpui-virtual-list-scroll-xvfb.log 2>&1 &
XVFB_PID=$!
trap 'kill "$XVFB_PID" 2>/dev/null || true; wait "$XVFB_PID" 2>/dev/null || true' EXIT
sleep 1

run_case() {
  local framework="$1" sample="$2" log app_pid window x y expected start end count elapsed
  log="/tmp/${framework}-virtual-list-scroll-${sample}.log"
  if [[ "$framework" == noir ]]; then
    DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$NOIR_BIN" "$NOIR_SCENE" >"$log" 2>&1 &
    expected='virtual-list scroll: list=telemetry-list from=4 to=5 row-tiles=\[5, 6, 7\]'
    x=300; y=180
  else
    DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan GPUI_SCROLL_TRACE=1 "$GPUI_BIN" >"$log" 2>&1 &
    expected='gpui-visible-range=5..8'
    x=300; y=120
  fi
  app_pid=$!
  sleep 2
  window=$(DISPLAY="$DISPLAY_NUM" xdotool search --onlyvisible --name '.*' | tail -n 1)
  start=$(date +%s%N)
  DISPLAY="$DISPLAY_NUM" xdotool mousemove --window "$window" "$x" "$y" click --repeat 3 --delay 0 5
  for _ in $(seq 1 400); do
    if grep -q "$expected" "$log"; then break; fi
    sleep 0.005
  done
  end=$(date +%s%N)
  count=$(grep -c "$expected" "$log" || true)
  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  if [[ "$count" -lt 1 ]]; then
    echo "${framework} sample ${sample}: did not reach bottom viewport" >&2
    tail -n 100 "$log" >&2
    return 1
  fi
  elapsed=$((end - start))
  printf '{"framework":"%s","sample":%d,"wheel_clicks":3,"end_viewport":"rows_5_to_7","completion_events":%d,"input_to_viewport_complete_ns":%d,"metric":"x11_wheel_to_endpoint_viewport_excluding_gpu_present"}\n' \
    "$framework" "$sample" "$count" "$elapsed" >>"$OUT"
}

for sample in $(seq 1 "$SAMPLES"); do
  run_case noir "$sample"
  run_case gpui "$sample"
done

echo "wrote $OUT"
