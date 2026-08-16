#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30
mkdir -p "$OUT"

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f "$OUT"/rounded-*.scene.json
}
trap cleanup EXIT

next_display() {
  local start="$1" display n
  for n in $(seq "$start" 320); do
    display=":$n"
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then
      printf '%s' "$display"
      return 0
    fi
  done
  return 1
}

start_xvfb() {
  local display="$1" log="$2"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >"$log" 2>&1 &
  pids+=("$!")
  local n="${display#:}"
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${n}" ]] && return 0; sleep 0.1; done
  echo "Xvfb failed for $display" >&2
  return 1
}

export_scene() {
  local module="$1" scene="$2"
  NOIR_ENTRY_MODULE="$module" PLTCOLLECTS="$ROOT:" racket "$ROOT/tools/export-dashboard.rkt" "$scene"
}

run_negative() {
  local mode="$1" scene display log status
  scene="$OUT/rounded-${mode}.scene.json"
  python3 "$ROOT/tools/mutate_rounded_surface_scene.py" "$OUT/log-browser-rounded.scene.json" "$scene" "$mode"
  display="$(next_display 260)"; log="/tmp/noir-rounded-${mode}.log"
  start_xvfb "$display" "${log}.xvfb"
  set +e
  DISPLAY="$display" WGPU_BACKEND=vulkan timeout 6 "$BIN" "$scene" >"$log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 124 || "$status" -eq 0 ]]; then
    echo "rounded ${mode} attack did not reject before event loop" >&2
    cat "$log" >&2
    exit 1
  fi
  grep -Eq 'rounded surface|rounded_surface_plan|desktop-wide visual Scene' "$log"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt > /tmp/noir-rounded-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-rounded-racket.log
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host > /tmp/noir-rounded-cargo.log 2>&1

export_scene examples/log-browser.rkt "$OUT/log-browser-rounded.scene.json"
export_scene examples/realtime-monitor.rkt "$OUT/realtime-monitor-rounded.scene.json"
python3 "$ROOT/tools/verify_visual_language_v2.py" log "$OUT/log-browser-rounded.scene.json"
python3 "$ROOT/tools/verify_visual_language_v2.py" monitor "$OUT/realtime-monitor-rounded.scene.json"
python3 - "$OUT/log-browser-rounded.scene.json" "$OUT/realtime-monitor-rounded.scene.json" <<'PY'
import json, sys
for path in sys.argv[1:]:
    scene = json.load(open(path, encoding='utf-8'))
    plan = scene['rounded_surface_plan']
    assert plan['abi_schema'] == 'noir-rounded-surface-plan-v1'
    assert plan['abi_revision'] == 1 and plan['aa_width_px'] == 1.0
    assert len(plan['surfaces']) >= 9
    assert all(item['radius_px'] > 0 and item['aa_width_px'] == 1.0 for item in plan['surfaces'])
print('rounded surface Scene oracle: PASS')
PY

for mode in radius offset geometry disable; do run_negative "$mode"; done

capture() {
  local scene="$1" image="$2" display log host
  display="$(next_display 280)"; log="/tmp/noir-rounded-positive-${display#:}.log"
  start_xvfb "$display" "${log}.xvfb"
  DISPLAY="$display" WGPU_BACKEND=vulkan "$BIN" "$scene" >"$log" 2>&1 & host=$!; pids+=("$host")
  sleep 3
  kill -0 "$host"
  DISPLAY="$display" xdotool mousemove 1260 700
  DISPLAY="$display" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${display}.0" -frames:v 1 "$image"
  grep -Fq 'compiler rounded surfaces: v1' "$log"
  kill "$host" 2>/dev/null || true
}

capture "$OUT/log-browser-rounded.scene.json" "$OUT/log-browser-rounded-v3-latest.png"
capture "$OUT/realtime-monitor-rounded.scene.json" "$OUT/realtime-monitor-rounded-v3-latest.png"

"$ROOT/tools/verify_log_browser.sh"
"$ROOT/tools/verify_realtime_monitor.sh"
printf '%s\n' 'ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS'
