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
  rm -f "$OUT"/material-focus-visual-mutate-*.scene.json
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 526 546); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then printf ':%s' "$n"; return 0; fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-modal-focus-visual-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2; return 1
}

expect_rejected() {
  local mode="$1" needle="$2" path status
  path="$OUT/material-focus-visual-mutate-${mode}.scene.json"
  python3 "$ROOT/tools/mutate_modal_focus_visual_scene.py" "$SCENE" "$mode" "$path" >/dev/null
  set +e
  DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$path" >"/tmp/noir-modal-focus-visual-${mode}.log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "modal focus visual mutation ${mode} was unexpectedly accepted" >&2
    cat "/tmp/noir-modal-focus-visual-${mode}.log" >&2
    return 1
  fi
  grep -Fq "$needle" "/tmp/noir-modal-focus-visual-${mode}.log"
  printf 'modal focus visual mutation %s: REJECTED\n' "$mode"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-modal-focus-visual-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-modal-focus-visual-racket.log
NOIR_ENTRY_MODULE=examples/material-overlay-showcase.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE"
python3 tools/verify_modal_focus_visual_plan_v1.py "$SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-modal-focus-visual-cargo.log 2>&1

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
EVIDENCE="$OUT/modal-focus-visual-evidence"
rm -rf "$EVIDENCE"; mkdir -p "$EVIDENCE"
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-modal-focus-visual-x11.log 2>&1 &
host_pid=$!; pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
win="$(DISPLAY="$DISPLAY" xdotool search --onlyvisible --name 'Noir' 2>/dev/null | tail -n1)"
DISPLAY="$DISPLAY" xdotool windowfocus --sync "$win"

# Open at the compiler-admitted initial slot, advance once, then Escape-close.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 392 324 click 1
sleep 0.35
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/01-modal-open-initial-ring.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Tab
sleep 0.25
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/02-modal-tab-second-ring.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Escape
sleep 0.30
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/03-modal-closed-rings-hidden.png"

# Exercise the remaining fixed ring edges and reverse path, then close with Enter.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 392 324 click 1
sleep 0.25
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Tab Tab Tab Tab Tab shift+Tab Return
sleep 0.40
kill -0 "$host_pid"
cp /tmp/noir-modal-focus-visual-x11.log "$EVIDENCE/x11-vulkan.log"
for needle in \
  'compiler modal focus visual: v1 entries=5 preallocated-outline-quads=5 halo=3px thickness=2px no-runtime-geometry' \
  'compiler modal focus GPU resources: ring-quads=5 metadata=5 alpha-initial=0' \
  'modal-focus: overlay=deployment-overlay transition=open focus-event-slot=3 focus-ring=Some(0) alpha-patches=1' \
  'modal-focus: overlay=deployment-overlay key=tab from-event-slot=3 to-event-slot=2 rings=0=>1 alpha-patches=2' \
  'modal-focus: overlay=deployment-overlay key=shift-tab from-event-slot=3 to-event-slot=6 rings=0=>4 alpha-patches=2' \
  'modal-focus: overlay=deployment-overlay transition=close restore-event-slot=0 focus-ring-alpha-clears=5' \
  'modal-focus: overlay=deployment-overlay key=enter event-slot=6 close-transition=true'; do
  grep -Fq "$needle" /tmp/noir-modal-focus-visual-x11.log
done
if [[ "$(grep -Fc 'event-map dispatch: overlay-open' /tmp/noir-modal-focus-visual-x11.log)" -ne 2 ]]; then
  echo 'modal focus visual background isolation failed: unexpected open dispatch count' >&2
  exit 1
fi
kill "$host_pid" 2>/dev/null || true
pids=("${pids[@]:0:${#pids[@]}-1}")

expect_rejected source 'invalid source instance offset'
expect_rejected geometry 'violates the fixed halo/outline/color recipe'
expect_rejected tile 'tile ID 1 exceeds compiled tile table'
expect_rejected disable 'marked modal_focus_visual_required may not disable'

# The independent focus-ring pass is also created with a zero-count sentinel for
# ordinary rounded applications. Run the established two-application compatibility suite.
bash "$ROOT/tools/verify_rounded_surface_plan.sh" >/tmp/noir-modal-focus-visual-rounded.log 2>&1
grep -Fq 'ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS' /tmp/noir-modal-focus-visual-rounded.log
printf '%s\n' 'MODAL_FOCUS_VISUAL_PLAN_V1_REGRESSION: PASS'
