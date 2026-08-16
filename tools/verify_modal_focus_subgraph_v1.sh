#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SCENE="$OUT/material-overlay-showcase.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30
mkdir -p "$OUT"

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f "$OUT"/material-modal-focus-mutate-*.scene.json
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 495 515); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then printf ':%s' "$n"; return 0; fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-modal-focus-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2; return 1
}

expect_rejected() {
  local mode="$1" needle="$2" path status
  path="$OUT/material-modal-focus-mutate-${mode}.scene.json"
  python3 "$ROOT/tools/mutate_modal_focus_subgraph_scene.py" "$SCENE" "$mode" "$path" >/dev/null
  set +e
  DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$path" >"/tmp/noir-modal-focus-${mode}.log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "modal focus mutation ${mode} was unexpectedly accepted" >&2
    cat "/tmp/noir-modal-focus-${mode}.log" >&2
    return 1
  fi
  grep -Fq "$needle" "/tmp/noir-modal-focus-${mode}.log"
  printf 'modal focus mutation %s: REJECTED\n' "$mode"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-modal-focus-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-modal-focus-racket.log
NOIR_ENTRY_MODULE=examples/material-overlay-showcase.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE"
python3 tools/verify_modal_focus_subgraph_v1.py "$SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-modal-focus-cargo.log 2>&1

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-modal-focus-x11.log 2>&1 &
host_pid=$!; pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
win="$(DISPLAY="$DISPLAY" xdotool search --onlyvisible --name 'Noir' 2>/dev/null | tail -n1)"
DISPLAY="$DISPLAY" xdotool windowfocus --sync "$win"
# Open, traverse fixed five-target ring, reverse once, then activate the selected target.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 392 324 click 1
sleep 0.35
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Tab Tab Tab Tab Tab shift+Tab
sleep 0.20
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Return
sleep 0.45
# Open again and close through the modal-priority Escape path.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 392 324 click 1
sleep 0.35
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Escape
sleep 0.45
for needle in \
  'compiler modal focus: v1 entries=1 fixed-tab-targets=5 background-isolated no-packets' \
  'modal-focus: overlay=deployment-overlay transition=open focus-event-slot=3' \
  'modal-focus: overlay=deployment-overlay key=tab from-event-slot=6 to-event-slot=3' \
  'modal-focus: overlay=deployment-overlay key=shift-tab from-event-slot=3 to-event-slot=6' \
  'modal-focus: overlay=deployment-overlay key=enter event-slot=6 close-transition=true' \
  'modal-focus: overlay=deployment-overlay transition=close restore-event-slot=0'; do
  grep -Fq "$needle" /tmp/noir-modal-focus-x11.log
done
if [[ "$(grep -Fc 'event-map dispatch: overlay-open' /tmp/noir-modal-focus-x11.log)" -ne 2 ]]; then
  echo 'modal focus background isolation failed: unexpected open dispatch count' >&2
  exit 1
fi
kill "$host_pid" 2>/dev/null || true
pids=("${pids[@]:0:${#pids[@]}-1}")

expect_rejected edge 'noncanonical Tab ring edge'
expect_rejected allowed 'allowed event set must equal'
expect_rejected tile 'tile ID 1 exceeds compiled tile table'
expect_rejected disable 'may not disable modal_focus_subgraph_plan v1'
printf '%s\n' 'MODAL_FOCUS_SUBGRAPH_V1_REGRESSION: PASS'
