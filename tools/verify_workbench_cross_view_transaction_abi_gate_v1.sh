#!/usr/bin/env bash
# Verify Rust ABI gate and static association proof. The fixed executor is tested by
# verify_workbench_cross_view_transaction_executor_v1.sh; this script only asserts admission/rejection.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SCENE="$OUT/material-observability-workbench-v2.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
MUTATOR="$ROOT/tools/mutate_workbench_cross_view_transaction_scene.py"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f "$OUT"/workbench-cross-view-mutate-*.scene.json
}
trap cleanup EXIT

next_display() {
  local number
  for number in $(seq 705 734); do
    if [[ ! -e "/tmp/.X${number}-lock" && ! -S "/tmp/.X11-unix/X${number}" ]]; then
      printf ':%s' "$number"
      return 0
    fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-cross-view-gate-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2
  return 1
}

expect_rejected() {
  local mode needle path status
  mode="$1"
  needle="$2"
  path="$OUT/workbench-cross-view-mutate-${mode}.scene.json"
  python3 "$MUTATOR" "$SCENE" "$mode" "$path"
  set +e
  DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$path" >"/tmp/noir-cross-view-gate-${mode}.log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "cross-view transaction mutation ${mode} was unexpectedly accepted" >&2
    cat "/tmp/noir-cross-view-gate-${mode}.log" >&2
    return 1
  fi
  grep -Fq "$needle" "/tmp/noir-cross-view-gate-${mode}.log"
  printf 'cross-view transaction mutation %s: REJECTED\n' "$mode"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-cross-view-gate-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-cross-view-gate-racket.log
NOIR_ENTRY_MODULE=examples/material-observability-workbench.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-cross-view-gate-export.log 2>&1
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-cross-view-gate-cargo.log 2>&1

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-cross-view-gate-x11.log 2>&1 &
host_pid=$!
pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
grep -Fq 'compiler workbench cross-view transaction: v1 id=workbench-acknowledge-alert-transaction' /tmp/noir-cross-view-gate-x11.log
grep -Fq 'source=alerts-data-view#observability-alert-stream target=overview-alert-ack-count glyph-lanes=8 row-color-lanes=3 tile-mask=0x1 executor=fixed-patch' /tmp/noir-cross-view-gate-x11.log
kill "$host_pid" 2>/dev/null || true
pids=("${pids[@]:0:${#pids[@]}-1}")

expect_rejected abi 'unsupported workbench_cross_view_transaction_plan ABI'
expect_rejected disable 'marked workbench_cross_view_transaction_required may not disable workbench_cross_view_transaction_plan v1'
expect_rejected action 'action slot disagrees with action id'
expect_rejected target 'Overview count glyph range is not the canonical dynamic state target'
printf '%s\n' 'WORKBENCH_CROSS_VIEW_TRANSACTION_ABI_GATE_V1_REGRESSION: PASS'
