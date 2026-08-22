#!/usr/bin/env bash
# Verify compiler-proved logical acknowledgement state: fixed bit table, idempotence,
# and compact-list recycle restoration. No performance sampling is performed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SCENE="$OUT/application-layer-workbench.scene.json"
COMPACT_SCENE="$OUT/application-layer-workbench-compact.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
EVIDENCE="$OUT/acknowledged-row-state-evidence"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

pids=()
cleanup() { for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT
next_display() {
  local number
  for number in $(seq 767 796); do
    if [[ ! -e "/tmp/.X${number}-lock" && ! -S "/tmp/.X11-unix/X${number}" ]]; then printf ':%s' "$number"; return 0; fi
  done
  return 1
}
start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-ack-row-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo 'Xvfb did not become ready' >&2; return 1
}

cd "$ROOT"
NOIR_ENTRY_MODULE=examples/application-layer-workbench.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-ack-row-export.log 2>&1
NOIR_ENTRY_MODULE=examples/application-layer-workbench-compact.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$COMPACT_SCENE" >/tmp/noir-ack-row-compact-export.log 2>&1
python3 tools/verify_application_layer_dsl_v1.py "$SCENE" operations "$COMPACT_SCENE" operations-compact >/tmp/noir-ack-row-oracle.log 2>&1
grep -Fq 'APPLICATION_DSL_ORACLE: application-layer-workbench.scene.json: PASS' /tmp/noir-ack-row-oracle.log
grep -Fq 'APPLICATION_DSL_ORACLE: application-layer-workbench-compact.scene.json: PASS' /tmp/noir-ack-row-oracle.log
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-ack-row-cargo.log 2>&1

# Reject malformed state ABI before any valid X11 host is started. Attack copies remain in
# out/ so the original compiler-owned relative font assets remain available to startup proof.
for mode in abi disable words owner; do
  target="$OUT/acknowledged-row-state-${mode}-mutated.scene.json"
  python3 tools/mutate_acknowledged_row_state_scene.py "$SCENE" "$mode" "$target"
  set +e
  "$BIN" "$target" >"/tmp/noir-ack-row-${mode}-mutation.log" 2>&1
  status=$?
  set -e
  test "$status" -ne 0
  case "$mode" in
    abi) grep -Eq 'unsupported acknowledged_row_state_plan ABI|expected noir-acknowledged-row-state-plan-v1' "/tmp/noir-ack-row-${mode}-mutation.log" ;;
    disable) grep -Fq 'acknowledged_row_state_required may not disable acknowledged_row_state_plan v1' "/tmp/noir-ack-row-${mode}-mutation.log" ;;
    words) grep -Fq 'invalid fixed u64 table geometry' "/tmp/noir-ack-row-${mode}-mutation.log" ;;
    owner) grep -Eq 'owner/list witness disagrees|owner is not the canonical Alerts' "/tmp/noir-ack-row-${mode}-mutation.log" ;;
  esac
  rm -f "$target"
done

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
mkdir -p "$EVIDENCE"
rm -f "$EVIDENCE"/*.png "$EVIDENCE"/x11-vulkan.log
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-ack-row-x11.log 2>&1 &
host_pid=$!
pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
win="$(DISPLAY="$DISPLAY" xdotool search --onlyvisible --name 'Noir' 2>/dev/null | tail -n1)"
test -n "$win"
DISPLAY="$DISPLAY" xdotool windowfocus --sync "$win"

# Alerts is owner value 2. A visible row release is the unique acknowledge action.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 110 218 click 1
sleep 0.25
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 420 200 click 1
sleep 0.35
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/01-alerts-acknowledged.png"
grep -Eq 'workbench-cross-view-transaction:.*alerts-logical=0.*ack-word=0.*state=0=>1' /tmp/noir-ack-row-x11.log

# Move row 0 out of the 3-slot physical ring, then restore it. The recovered lane must
# query the same fixed bit and redraw the acknowledged visual without another transaction.
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Page_Down
sleep 0.30
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Home
sleep 0.35
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/02-alerts-recycled-restored.png"
grep -Eq 'list-interaction-patch:.*logical=0.*acknowledged=true' /tmp/noir-ack-row-x11.log

# A second activation of retained logical row 0 is idempotently consumed before state/GPU writes.
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Return
sleep 0.25
grep -Eq 'workbench-cross-view-transaction-gated:.*reason=already-acknowledged logical=0.*state-writes=0 gpu-writes=0' /tmp/noir-ack-row-x11.log
test "$(grep -Ec '^workbench-cross-view-transaction: ' /tmp/noir-ack-row-x11.log)" -eq 1

DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 110 94 click 1
sleep 0.30
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/03-overview-count-once.png"
grep -Eq 'workbench-cross-view-transaction:.*state=0=>1' /tmp/noir-ack-row-x11.log
cp /tmp/noir-ack-row-x11.log "$EVIDENCE/x11-vulkan.log"
for image in "$EVIDENCE"/*.png; do test -s "$image"; done
printf '%s\n' 'ACKNOWLEDGED_ROW_STATE_EXECUTOR_V1_REGRESSION: PASS'
