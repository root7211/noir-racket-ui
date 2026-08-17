#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SCENE="$OUT/material-observability-workbench.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f "$OUT"/material-workbench-mutate-*.scene.json
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 552 572); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then printf ':%s' "$n"; return 0; fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-workbench-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2
  return 1
}

expect_rejected() {
  local mode="$1" needle="$2" path status
  path="$OUT/material-workbench-mutate-${mode}.scene.json"
  python3 "$ROOT/tools/mutate_material_observability_workbench_scene.py" "$SCENE" "$mode" "$path" >/dev/null
  set +e
  DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$path" >"/tmp/noir-workbench-mutate-${mode}.log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "material workbench mutation ${mode} was unexpectedly accepted" >&2
    cat "/tmp/noir-workbench-mutate-${mode}.log" >&2
    return 1
  fi
  grep -Fq "$needle" "/tmp/noir-workbench-mutate-${mode}.log"
  printf 'material workbench mutation %s: REJECTED\n' "$mode"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-workbench-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-workbench-racket.log
NOIR_ENTRY_MODULE=examples/material-observability-workbench.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE"
python3 tools/verify_material_observability_workbench_plan_v1.py "$SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-workbench-cargo.log 2>&1

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
EVIDENCE="$OUT/material-observability-workbench-evidence"
mkdir -p "$EVIDENCE"
rm -f "$EVIDENCE"/*.png "$EVIDENCE"/x11-vulkan.log
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-workbench-x11.log 2>&1 &
host_pid=$!; pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
win="$(DISPLAY="$DISPLAY" xdotool search --onlyvisible --name 'Noir' 2>/dev/null | tail -n1)"
test -n "$win"
DISPLAY="$DISPLAY" xdotool windowfocus --sync "$win"

# Rail endpoints: Overview -> Systems (page/row input) -> Alerts (input is gated).
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/01-overview-initial.png"
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 110 156 click 1
sleep 0.35
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/02-systems-active.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Page_Down
sleep 0.20
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 420 230 click 1
sleep 0.25
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/03-systems-list-navigation-selection.png"
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 110 218 click 1
sleep 0.35
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/04-alerts-active.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Page_Down
sleep 0.20

# Global overlay retains its existing focus graph and independent ring pass.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 1120 64 click 1
sleep 0.30
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/05-overlay-initial-focus.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Tab
sleep 0.22
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/06-overlay-tab-focus.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Escape
sleep 0.30
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/07-overlay-closed-alerts-active.png"
kill -0 "$host_pid"
cp /tmp/noir-workbench-x11.log "$EVIDENCE/x11-vulkan.log"

for image in "$EVIDENCE"/*.png; do test -s "$image"; done
for needle in \
  'compiler material workbench: v1 id=observability-workbench rail=observability-rail views=3' \
  'material workbench initial alpha: selected=observability-overview' \
  'material-workbench view-switch: old=observability-overview new=observability-systems' \
  'list-navigation-plan: id=observability-list-navigation key=PageDown' \
  'list-selection: list=observability-log logical=4 physical=0' \
  'material-workbench view-switch: old=observability-systems new=observability-alerts' \
  'material-workbench list-input-gated: active-view=observability-alerts systems-view=observability-systems' \
  'modal-focus: overlay=observability-deployment-overlay transition=open focus-event-slot=7 focus-ring=Some(0)' \
  'modal-focus: overlay=observability-deployment-overlay key=tab from-event-slot=7 to-event-slot=6 rings=0=>1 alpha-patches=2' \
  'modal-focus: overlay=observability-deployment-overlay transition=close restore-event-slot=3 focus-ring-alpha-clears=5'; do
  grep -Fq "$needle" /tmp/noir-workbench-x11.log
done
kill "$host_pid" 2>/dev/null || true
pids=("${pids[@]:0:${#pids[@]}-1}")

expect_rejected offset 'instance address set is not its canonical subtree'
expect_rejected node 'invalid canonical static subtree witness'
expect_rejected tile 'tile scope is not its canonical static subtree union'
expect_rejected disable 'marked material_observability_workbench_required may not disable'

bash "$ROOT/tools/verify_rounded_surface_plan.sh" >/tmp/noir-workbench-rounded.log 2>&1
grep -Fq 'ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS' /tmp/noir-workbench-rounded.log
printf '%s\n' 'MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_V1_REGRESSION: PASS'
