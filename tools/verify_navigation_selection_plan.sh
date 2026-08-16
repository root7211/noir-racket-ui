#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SCENE="$OUT/material-profile-navigation-v1.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30
mkdir -p "$OUT"

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f "$OUT"/material-profile-navigation-mutate-*.scene.json
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 380 400); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then
      printf ':%s' "$n"
      return 0
    fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-navigation-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2
  return 1
}

expect_rejected() {
  local mode="$1" needle="$2" path
  path="$OUT/material-profile-navigation-mutate-${mode}.scene.json"
  python3 "$ROOT/tools/mutate_navigation_selection_scene.py" "$SCENE" "$mode" "$path" >/dev/null
  set +e
  DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$path" >"/tmp/noir-navigation-${mode}.log" 2>&1
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "navigation mutation ${mode} was unexpectedly accepted" >&2
    cat "/tmp/noir-navigation-${mode}.log" >&2
    return 1
  fi
  grep -Fq "$needle" "/tmp/noir-navigation-${mode}.log"
  printf 'navigation mutation %s: REJECTED\n' "$mode"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-navigation-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-navigation-racket.log
NOIR_ENTRY_MODULE=examples/material-profile-dashboard.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE"
python3 tools/verify_navigation_selection_plan.py "$SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-navigation-cargo.log 2>&1

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-navigation-x11.log 2>&1 &
host_pid=$!
pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-profile-navigation-before.png"
DISPLAY="$DISPLAY" xdotool mousemove 122 144 click 1
sleep 1
DISPLAY="$DISPLAY" xdotool mousemove 1260 700
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-profile-navigation-systems.png"
DISPLAY="$DISPLAY" xdotool mousemove 122 208 click 1
sleep 1
DISPLAY="$DISPLAY" xdotool mousemove 1260 700
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-profile-navigation-v1.png"
grep -Fq 'compiler navigation selection: rail=material-nav-rail state=material-navigation slot=0 destinations=3 initial=material-overview' /tmp/noir-navigation-x11.log
grep -Fq 'navigation-selection: rail=material-nav-rail old=material-overview new=material-systems state-slot=0 target=1 color-patches=2 tile-mask=0x0000000000000006 worklist=no-packets' /tmp/noir-navigation-x11.log
grep -Fq 'navigation-selection: rail=material-nav-rail old=material-systems new=material-alerts state-slot=0 target=2 color-patches=2 tile-mask=0x000000000000000c worklist=no-packets' /tmp/noir-navigation-x11.log
grep -Fq 'state-slot write: action=material-select-systems state=material-navigation index=0 op=set value=1' /tmp/noir-navigation-x11.log
grep -Fq 'state-slot write: action=material-select-alerts state=material-navigation index=0 op=set value=2' /tmp/noir-navigation-x11.log
kill "$host_pid" 2>/dev/null || true
pids=(${pids[@]:0:${#pids[@]}-1})

expect_rejected target 'duplicate or non-canonical destination transition'
expect_rejected offset 'source instance witness is invalid'
expect_rejected tile 'widened or mismatched local tile scope'
expect_rejected disable 'may not disable navigation_selection_plan v1'
printf '%s\n' 'NAVIGATION_SELECTION_PLAN_V1_REGRESSION: PASS'
