#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN=/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin
PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true; done
  rm -f "$ROOT"/out/noir-visual-language-*.scene.json
}
trap cleanup EXIT INT TERM

find_display() {
  local candidate
  for candidate in $(seq 100 199); do
    if [[ ! -e "/tmp/.X${candidate}-lock" && ! -S "/tmp/.X11-unix/X${candidate}" ]]; then
      printf ':%s\n' "$candidate"
      return 0
    fi
  done
  echo "no free X11 display for visual language proof" >&2
  return 1
}

start_xvfb() {
  local display=$1 label=$2
  Xvfb "$display" -screen 0 1280x720x24 >"/tmp/noir-visual-v2-${label}-xvfb.log" 2>&1 &
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

capture_scene() {
  local scene=$1 label=$2 output=$3 display xvfb host
  display=$(find_display)
  start_xvfb "$display" "$label"
  xvfb=$LAST_XVFB_PID
  DISPLAY="$display" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
    "$BIN" "$scene" >"/tmp/noir-visual-v2-${label}.log" 2>&1 &
  host=$!
  PIDS+=("$host")
  sleep 4
  kill -0 "$host"
  DISPLAY="$display" xdotool mousemove 1270 710 >/dev/null 2>&1 || true
  ffmpeg -hide_banner -loglevel error -y -f x11grab -video_size 1280x720 \
    -i "$display.0+0,0" -frames:v 1 "$output"
  test -s "$output"
  stop_pid "$host"
  stop_pid "$xvfb"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-visual-v2-racket-tests.log 2>&1
PATH="$TOOLCHAIN:$PATH" RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30 CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30 \
  "$TOOLCHAIN/cargo" build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host \
  >/tmp/noir-visual-v2-build.log 2>&1

for module in log-browser realtime-monitor; do
  NOIR_ENTRY_MODULE="examples/${module}.rkt" PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt "$ROOT/out/${module}.scene.json" \
    >"/tmp/noir-visual-v2-${module}-export.log" 2>&1
done

python3 tools/verify_visual_language_v2.py log out/log-browser.scene.json \
  >/tmp/noir-visual-v2-log-structure.json
python3 tools/verify_visual_language_v2.py monitor out/realtime-monitor.scene.json \
  >/tmp/noir-visual-v2-monitor-structure.json
grep -F '"status": "PASS"' /tmp/noir-visual-v2-log-structure.json >/dev/null
grep -F '"status": "PASS"' /tmp/noir-visual-v2-monitor-structure.json >/dev/null

# The visual canvas remains a versioned compiler-owned contract. All three mutations
# must be rejected before the first frame; visual v2 does not weaken the v1 ABI gate.
for kind in schema preset canvas; do
  tampered="$ROOT/out/noir-visual-language-${kind}.scene.json"
  python3 tools/mutate_visual_language_scene.py "$kind" "$ROOT/out/log-browser.scene.json" "$tampered" >/dev/null
  display=$(find_display)
  start_xvfb "$display" "tamper-${kind}"
  xvfb=$LAST_XVFB_PID
  set +e
  DISPLAY="$display" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
    "$BIN" "$tampered" >"/tmp/noir-visual-v2-${kind}.log" 2>&1
  status=$?
  set -e
  stop_pid "$xvfb"
  [[ $status -ne 0 ]]
  case "$kind" in
    schema) grep -F 'unsupported visual_language_plan payload' "/tmp/noir-visual-v2-${kind}.log" >/dev/null ;;
    preset) grep -F 'unsupported preset unbounded-desktop' "/tmp/noir-visual-v2-${kind}.log" >/dev/null ;;
    canvas) grep -F 'geometry must be 1280x720 margin 32' "/tmp/noir-visual-v2-${kind}.log" >/dev/null ;;
  esac
done

./tools/verify_desktop_component_macros.sh >/tmp/noir-visual-v2-components.log 2>&1
./tools/verify_font_placement_scene.sh >/tmp/noir-visual-v2-font.log 2>&1
./tools/verify_log_browser.sh >/tmp/noir-visual-v2-log.log 2>&1
./tools/verify_realtime_monitor.sh >/tmp/noir-visual-v2-monitor.log 2>&1

capture_scene "$ROOT/out/log-browser.scene.json" log-browser "$ROOT/out/log-browser-visual-language-v2.png"
capture_scene "$ROOT/out/realtime-monitor.scene.json" realtime-monitor "$ROOT/out/realtime-monitor-visual-language-v2.png"

echo "visual language v2 regression: PASS"
