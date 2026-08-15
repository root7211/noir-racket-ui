#!/usr/bin/env bash
# Exploratory end-to-end X11 input-to-handler benchmark. This deliberately does
# NOT claim GPU frame time: Noir exposes wgpu timestamps, while GPUI 0.2.2 does
# not expose a matching portable timestamp API in this minimal comparator. Mouse
# events are injected as a zero-delay X11 burst; the metric ends at all handler logs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLES="${1:-10}"
CLICKS="${2:-25}"
OUT="$ROOT/wgpu-verify/out/noir-gpui-virtual-list-input-samples.jsonl"
NOIR_BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
NOIR_SCENE="$ROOT/out/virtual-list-dashboard.scene.json"
GPUI_BIN="$ROOT/gpui-virtual-list-benchmark/target/release/gpui-virtual-list-benchmark"
DISPLAY_NUM=:92
: >"$OUT"

Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 >/tmp/noir-gpui-virtual-list-xvfb.log 2>&1 &
XVFB_PID=$!
trap 'kill "$XVFB_PID" 2>/dev/null || true; wait "$XVFB_PID" 2>/dev/null || true' EXIT
sleep 1

run_case() {
  local framework="$1" sample="$2" log app_pid window start end count expected x y elapsed
  log="/tmp/${framework}-virtual-list-${sample}.log"
  if [[ "$framework" == noir ]]; then
    DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$NOIR_BIN" "$NOIR_SCENE" >"$log" 2>&1 &
    expected='state-slot write: action=refresh-list'
    x=300; y=261
  else
    DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$GPUI_BIN" >"$log" 2>&1 &
    expected='gpui-refresh-event count='
    x=300; y=210
  fi
  app_pid=$!
  sleep 2
  window=$(DISPLAY="$DISPLAY_NUM" xdotool search --onlyvisible --name '.*' | tail -n 1)
  start=$(date +%s%N)
  DISPLAY="$DISPLAY_NUM" xdotool mousemove --window "$window" "$x" "$y" click --repeat "$CLICKS" --delay 0 1
  for _ in $(seq 1 300); do
    count=$(grep -c "$expected" "$log" || true)
    if [[ "$count" -ge "$CLICKS" ]]; then break; fi
    sleep 0.01
  done
  end=$(date +%s%N)
  count=$(grep -c "$expected" "$log" || true)
  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  if [[ "$count" -ne "$CLICKS" ]]; then
    echo "${framework} sample ${sample}: observed ${count}/${CLICKS} event(s)" >&2
    tail -n 80 "$log" >&2
    return 1
  fi
  elapsed=$((end - start))
  printf '{"framework":"%s","sample":%d,"clicks":%d,"completed_events":%d,"input_to_all_handlers_ns":%d,"ns_per_handler":%.3f,"metric":"x11_input_to_handler_excluding_gpu_present"}\n' \
    "$framework" "$sample" "$CLICKS" "$count" "$elapsed" "$(awk -v t="$elapsed" -v n="$CLICKS" 'BEGIN { print t / n }')" >>"$OUT"
}

for sample in $(seq 1 "$SAMPLES"); do
  run_case noir "$sample"
  run_case gpui "$sample"
done

echo "wrote $OUT"
