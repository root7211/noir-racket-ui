#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLCHAIN=/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
OUT="$ROOT/out"
LOG_SCENE="$OUT/log-browser-page3.scene.json"
MONITOR_SCENE="$OUT/realtime-monitor-page3.scene.json"
RUN_LOG=/tmp/noir-dynamic-font-cell-v1.log
DISPLAY_BASE=206
PIDS=()

cleanup() {
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f "$OUT"/dynamic-font-cell-{face,uv,word-offset}.scene.json
}
trap cleanup EXIT

find_display() {
  local n="$DISPLAY_BASE"
  while [[ -e "/tmp/.X${n}-lock" || -e "/tmp/.X11-unix/X${n}" ]]; do n=$((n + 1)); done
  echo ":${n}"
}

export_scene() {
  local module="$1" destination="$2"
  NOIR_ENTRY_MODULE="$module" PLTCOLLECTS="$ROOT:" racket "$ROOT/tools/export-dashboard.rkt" "$destination"
}

run_positive() {
  local scene="$1" label="$2" display
  display=$(find_display); DISPLAY_BASE=$((DISPLAY_BASE + 1))
  Xvfb "$display" -screen 0 1280x720x24 >"/tmp/noir-${label}-xvfb.log" 2>&1 &
  local xpid=$!; PIDS+=("$xpid"); sleep 1
  set +e
  DISPLAY="$display" XDG_RUNTIME_DIR=/tmp LIBGL_ALWAYS_SOFTWARE=1 WGPU_BACKEND=vulkan timeout 6s "$BIN" "$scene" >"/tmp/noir-${label}.log" 2>&1
  local status=$?
  set -e
  [[ "$status" == 124 ]] || { cat "/tmp/noir-${label}.log"; return 1; }
  grep -F "compiler dynamic font cells:" "/tmp/noir-${label}.log"
  grep -F "dynamic-font-cell-atlas-upload: page=3" "/tmp/noir-${label}.log"
  grep -F "page=3" "/tmp/noir-${label}.log" | grep -F "glyph-direct-draw"
}

run_reject() {
  local scene="$1" expected="$2" label="$3" display
  display=$(find_display); DISPLAY_BASE=$((DISPLAY_BASE + 1))
  Xvfb "$display" -screen 0 1280x720x24 >"/tmp/noir-${label}-xvfb.log" 2>&1 &
  local xpid=$!; PIDS+=("$xpid"); sleep 1
  set +e
  DISPLAY="$display" XDG_RUNTIME_DIR=/tmp LIBGL_ALWAYS_SOFTWARE=1 WGPU_BACKEND=vulkan timeout 5s "$BIN" "$scene" >"/tmp/noir-${label}.log" 2>&1
  local status=$?
  set -e
  [[ "$status" != 0 && "$status" != 124 ]] || { cat "/tmp/noir-${label}.log"; return 1; }
  grep -F "$expected" "/tmp/noir-${label}.log"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt > /tmp/noir-dynamic-font-cell-racket.log
export_scene examples/log-browser.rkt "$LOG_SCENE"
export_scene examples/realtime-monitor.rkt "$MONITOR_SCENE"

python3 - "$LOG_SCENE" <<'PY'
import json, sys
scene = json.load(open(sys.argv[1], encoding='utf-8'))
plan = scene['dynamic_font_cell_plan']
assert plan['abi_schema'] == 'noir-dynamic-font-cell-plan-v1'
assert plan['atlas_page'] == 3 and plan['glyph_domain_count'] == 37
assert plan['fixed_advance'] == 10.0 and len(plan['tables']) == 1
cells = plan['tables'][0]
assert len(cells['placement_slots']) == len(cells['glyph_word_offsets']) == len(cells['cell_uv']) == len(cells['cell_advance'])
assert all(value == 10.0 for value in cells['cell_advance'])
print('dynamic-font-cell Scene evidence: page=3 dense=37 fixed-advance=10 table-cells=%d' % len(cells['placement_slots']))
PY

PATH="$TOOLCHAIN:$PATH" RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30 CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30 cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host > /tmp/noir-dynamic-font-cell-build.log
run_positive "$LOG_SCENE" dynamic-font-cell-log
run_positive "$MONITOR_SCENE" dynamic-font-cell-monitor

for kind in face uv word-offset; do
  target="$OUT/dynamic-font-cell-${kind}.scene.json"
  python3 "$ROOT/tools/mutate_dynamic_font_cell_scene.py" "$LOG_SCENE" "$target" "$kind"
  case "$kind" in
    face) run_reject "$target" "uses unsupported face/page/coverage/advance policy" "dynamic-font-cell-face" ;;
    uv) run_reject "$target" "escapes page-3 fixed-cell proof" "dynamic-font-cell-uv" ;;
    word-offset) run_reject "$target" "escapes page-3 fixed-cell proof" "dynamic-font-cell-word-offset" ;;
  esac
done

"$ROOT/tools/verify_log_browser.sh" > /tmp/noir-dynamic-font-cell-log-browser-regression.log
"$ROOT/tools/verify_realtime_monitor.sh" > /tmp/noir-dynamic-font-cell-monitor-regression.log
printf '%s\n' 'DYNAMIC_FONT_CELL_PLAN_V1: PASS'
