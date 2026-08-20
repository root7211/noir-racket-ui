#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SCENE="$OUT/material-observability-workbench-v2.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f "$OUT"/material-workbench-v2-mutate-*.scene.json
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 613 642); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then printf ':%s' "$n"; return 0; fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-workbench-v2-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2
  return 1
}

expect_rejected() {
  local mode="$1" needle="$2" path status
  path="$OUT/material-workbench-v2-mutate-${mode}.scene.json"
  python3 "$ROOT/tools/mutate_material_observability_workbench_v2_scene.py" "$SCENE" "$mode" "$path" >/dev/null
  set +e
  DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$path" >"/tmp/noir-workbench-v2-mutate-${mode}.log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "material workbench v2 mutation ${mode} was unexpectedly accepted" >&2
    cat "/tmp/noir-workbench-v2-mutate-${mode}.log" >&2
    return 1
  fi
  grep -Fq "$needle" "/tmp/noir-workbench-v2-mutate-${mode}.log"
  printf 'material workbench v2 mutation %s: REJECTED\n' "$mode"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-workbench-v2-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-workbench-v2-racket.log
NOIR_ENTRY_MODULE=examples/material-observability-workbench.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE"
python3 tools/verify_material_observability_workbench_plan_v2.py "$SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-workbench-v2-cargo.log 2>&1

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
EVIDENCE="$OUT/material-observability-workbench-v2-evidence"
mkdir -p "$EVIDENCE"
rm -f "$EVIDENCE"/*.png "$EVIDENCE"/x11-vulkan.log
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-workbench-v2-x11.log 2>&1 &
host_pid=$!; pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
win="$(DISPLAY="$DISPLAY" xdotool search --onlyvisible --name 'Noir' 2>/dev/null | tail -n1)"
test -n "$win"
DISPLAY="$DISPLAY" xdotool windowfocus --sync "$win"

# Overview has no admitted data arena: PageDown must produce no list GPU path.
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/01-overview-initial.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Page_Down
sleep 0.20

# Systems owns the first 10000x4 compact arena.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 110 156 click 1
sleep 0.35
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Page_Down
sleep 0.20
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 420 230 click 1
sleep 0.25
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/02-systems-data-active.png"

# Alerts owns the independent 2048x3 compact arena at the same list geometry.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 110 218 click 1
sleep 0.35
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Page_Down
sleep 0.20
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 420 230 click 1
sleep 0.25
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/03-alerts-data-active.png"

# Global overlay preserves the admitted modal subgraph and independent focus outline pass.
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 1120 64 click 1
sleep 0.30
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/04-overlay-initial-focus.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Tab
sleep 0.22
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/05-overlay-tab-focus.png"
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Escape
sleep 0.30
DISPLAY="$DISPLAY" python3 tools/capture_x11_window.py "$win" "$EVIDENCE/06-overlay-closed-alerts.png"
kill -0 "$host_pid"
cp /tmp/noir-workbench-v2-x11.log "$EVIDENCE/x11-vulkan.log"

for image in "$EVIDENCE"/*.png; do test -s "$image"; done
for needle in \
  'compiler material workbench: v2 id=observability-workbench rail=observability-rail views=3 data-views=2' \
  'material workbench initial alpha: selected=observability-overview' \
  'material-workbench list-navigation-gated: active-view=observability-overview key=PageDown no-owner-arena' \
  'material-workbench view-switch: old=observability-overview new=observability-systems' \
  'list-navigation-plan: id=observability-list-navigation key=PageDown' \
  'list-selection: list=observability-log logical=4 physical=0' \
  'material-workbench view-switch: old=observability-systems new=observability-alerts' \
  'list-navigation-plan: id=observability-alert-list-navigation key=PageDown' \
  'list-selection: list=observability-alert-stream logical=3 physical=0' \
  'modal-focus: overlay=observability-deployment-overlay transition=open' \
  'modal-focus: overlay=observability-deployment-overlay key=tab' \
  'modal-focus: overlay=observability-deployment-overlay transition=close'; do
  grep -Fq "$needle" /tmp/noir-workbench-v2-x11.log
done
kill "$host_pid" 2>/dev/null || true
pids=("${pids[@]:0:${#pids[@]}-1}")

expect_rejected offset 'instance address set is not its canonical list subtree'
expect_rejected node 'invalid canonical owner subtree witness'
expect_rejected tile 'tile scope is not its canonical list subtree union'
expect_rejected disable 'marked material_observability_workbench_required may not disable material_observability_workbench_plan v2'

bash "$ROOT/tools/verify_rounded_surface_plan.sh" >/tmp/noir-workbench-v2-rounded.log 2>&1
grep -Fq 'ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS' /tmp/noir-workbench-v2-rounded.log
printf '%s\n' 'MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_V2_REGRESSION: PASS'
