#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN=/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin
SCENES=("log-browser.scene.json" "realtime-monitor.scene.json")
PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done
  rm -f "$ROOT"/out/noir-visual-language-*.scene.json
}
trap cleanup EXIT INT TERM

find_display() {
  local candidate
  for candidate in $(seq 510 560); do
    if [[ ! -e "/tmp/.X${candidate}-lock" && ! -S "/tmp/.X11-unix/X${candidate}" ]]; then
      printf ':%s\n' "$candidate"
      return 0
    fi
  done
  echo "no free X11 display for visual language proof" >&2
  return 1
}

start_xvfb() {
  local display=$1
  Xvfb "$display" -screen 0 1280x720x24 >/tmp/noir-visual-language-xvfb.log 2>&1 &
  LAST_XVFB_PID=$!
  PIDS+=("$LAST_XVFB_PID")
  sleep 1
  kill -0 "$LAST_XVFB_PID"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-visual-language-racket-tests.log 2>&1
PATH="$TOOLCHAIN:$PATH" RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30 CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30 \
  "$TOOLCHAIN/cargo" build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host >/tmp/noir-visual-language-build.log 2>&1

for module in log-browser realtime-monitor; do
  NOIR_ENTRY_MODULE="examples/${module}.rkt" PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt "$ROOT/out/${module}.scene.json" >/tmp/noir-visual-language-${module}-export.log 2>&1
  python3 tools/audit_visual_canvas.py "$ROOT/out/${module}.scene.json" >/tmp/noir-visual-language-${module}-audit.json
  grep -F '"violation_count": 0' /tmp/noir-visual-language-${module}-audit.json >/dev/null
  grep -F '"preset": "desktop-wide"' /tmp/noir-visual-language-${module}-audit.json >/dev/null
done

for kind in schema preset canvas; do
  tampered="$ROOT/out/noir-visual-language-${kind}.scene.json"
  python3 tools/mutate_visual_language_scene.py "$kind" "$ROOT/out/log-browser.scene.json" "$tampered" >/dev/null
  display=$(find_display)
  start_xvfb "$display"
  xvfb=$LAST_XVFB_PID
  set +e
  DISPLAY="$display" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" "$tampered" >/tmp/noir-visual-language-${kind}.log 2>&1
  status=$?
  set -e
  kill "$xvfb" 2>/dev/null || true
  wait "$xvfb" 2>/dev/null || true
  [[ $status -ne 0 ]]
  case "$kind" in
    schema) grep -F 'unsupported visual_language_plan payload' /tmp/noir-visual-language-${kind}.log >/dev/null ;;
    preset) grep -F 'unsupported preset unbounded-desktop' /tmp/noir-visual-language-${kind}.log >/dev/null ;;
    canvas) grep -F 'geometry must be 1280x720 margin 32' /tmp/noir-visual-language-${kind}.log >/dev/null ;;
  esac
done

./tools/verify_font_placement_scene.sh >/tmp/noir-visual-language-font.log 2>&1
./tools/verify_log_browser.sh >/tmp/noir-visual-language-log.log 2>&1
./tools/verify_realtime_monitor.sh >/tmp/noir-visual-language-monitor.log 2>&1

echo "visual language v1 regression: PASS"
