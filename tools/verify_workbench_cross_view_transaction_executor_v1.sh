#!/usr/bin/env bash
# Verify the compiler-proved fixed executor. No performance sampling is performed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SCENE="$OUT/material-observability-workbench-v2.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
EVIDENCE="$OUT/workbench-cross-view-transaction-evidence"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT

next_display() {
  local number
  for number in $(seq 737 766); do
    if [[ ! -e "/tmp/.X${number}-lock" && ! -S "/tmp/.X11-unix/X${number}" ]]; then
      printf ':%s' "$number"
      return 0
    fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-cross-view-executor-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2
  return 1
}

cd "$ROOT"
# Keep ABI/object shape attacks separate from valid execution behavior.
bash tools/verify_workbench_cross_view_transaction_abi_gate_v1.sh >/tmp/noir-cross-view-executor-gate.log 2>&1
grep -Fq 'WORKBENCH_CROSS_VIEW_TRANSACTION_ABI_GATE_V1_REGRESSION: PASS' /tmp/noir-cross-view-executor-gate.log

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
mkdir -p "$EVIDENCE"
rm -f "$EVIDENCE"/*.png "$EVIDENCE"/x11-vulkan.log
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-cross-view-executor-x11.log 2>&1 &
host_pid=$!
pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
win="$(DISPLAY="$DISPLAY" xdotool search --onlyvisible --name 'Noir' 2>/dev/null | tail -n1)"
test -n "$win"
DISPLAY="$DISPLAY" xdotool windowfocus --sync "$win"

# Alerts is the only view that owns the admitted source arena. Calling the fixed
# button before a row selection must consume the action but issue zero writes.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 110 218 click 1
sleep 0.30
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 1100 610 click 1
sleep 0.25
grep -Fq 'workbench-cross-view-transaction-gated: id=workbench-acknowledge-alert-transaction origin=pointer reason=no-alert-selection state-writes=0 gpu-writes=0' /tmp/noir-cross-view-executor-x11.log

# A visible Alerts row owns the canonical row-activation action. Its release performs
# one bounded patch set: 1 state, 1 color lane, 29 detail glyphs and 8 Overview glyphs.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 420 230 click 1
sleep 0.35
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/01-alerts-after-ack.png"

# Only then expose the cross-view target endpoint.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 110 94 click 1
sleep 0.35
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/02-overview-count-after-ack.png"

# Enter has a retained Alerts selection but Overview owns no data arena. It must not
# run the transaction a second time.
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Return
sleep 0.25
grep -Fq 'material-workbench list-input-gated: active-view=observability-overview requested-list=1 owner-view=observability-alerts' /tmp/noir-cross-view-executor-x11.log
grep -Fq 'workbench-cross-view-transaction: id=workbench-acknowledge-alert-transaction origin=row-activation' /tmp/noir-cross-view-executor-x11.log
grep -Fq 'state-writes=1 row-color-writes=1 detail-glyph-writes=29 overview-count-glyph-writes=8 tile-mask=0x0000000000000001 worklist=no-packets' /tmp/noir-cross-view-executor-x11.log
test "$(grep -Fc 'workbench-cross-view-transaction: id=workbench-acknowledge-alert-transaction' /tmp/noir-cross-view-executor-x11.log)" -eq 1
cp /tmp/noir-cross-view-executor-x11.log "$EVIDENCE/x11-vulkan.log"
for image in "$EVIDENCE"/*.png; do test -s "$image"; done
bash "$ROOT/tools/verify_rounded_surface_plan.sh" >/tmp/noir-cross-view-executor-rounded.log 2>&1
grep -Fq 'ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS' /tmp/noir-cross-view-executor-rounded.log
printf '%s\n' 'WORKBENCH_CROSS_VIEW_TRANSACTION_EXECUTOR_V1_REGRESSION: PASS'
