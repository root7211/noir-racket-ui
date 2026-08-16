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
  rm -f "$OUT"/material-overlay-mutate-*.scene.json
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 470 490); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then printf ':%s' "$n"; return 0; fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-overlay-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2; return 1
}

expect_rejected() {
  local mode="$1" needle="$2" path status
  path="$OUT/material-overlay-mutate-${mode}.scene.json"
  python3 "$ROOT/tools/mutate_overlay_state_scene.py" "$SCENE" "$mode" "$path" >/dev/null
  set +e
  DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$path" >"/tmp/noir-overlay-${mode}.log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "overlay mutation ${mode} was unexpectedly accepted" >&2
    cat "/tmp/noir-overlay-${mode}.log" >&2
    return 1
  fi
  grep -Fq "$needle" "/tmp/noir-overlay-${mode}.log"
  printf 'overlay mutation %s: REJECTED\n' "$mode"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-overlay-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-overlay-racket.log
NOIR_ENTRY_MODULE=examples/material-overlay-showcase.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE"
python3 tools/verify_overlay_state_plan.py "$SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-overlay-cargo.log 2>&1

DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-overlay-x11.log 2>&1 &
host_pid=$!; pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
win="$(DISPLAY="$DISPLAY" xdotool search --onlyvisible --name 'Noir' 2>/dev/null | tail -n1)"
DISPLAY="$DISPLAY" xdotool windowfocus --sync "$win" 2>/dev/null || true
# open then Escape close
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 392 324 click 1
sleep 0.35
DISPLAY="$DISPLAY" xdotool key --window "$win" --clearmodifiers Escape
sleep 0.45
# open then confirm close
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 392 324 click 1
sleep 0.35
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 812 416 click 1
sleep 0.45
# open then menu copy close
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 392 324 click 1
sleep 0.35
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 1040 236 click 1
sleep 0.45
# open then scrim close; retain before/open/closed real X11 evidence
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 392 324 click 1
sleep 0.35
DISPLAY="$DISPLAY" xdotool mousemove 1260 700
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-overlay-open-v1.png"
DISPLAY="$DISPLAY" xdotool mousemove --window "$win" 1100 560 click 1
sleep 0.45
DISPLAY="$DISPLAY" xdotool mousemove 1260 700
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-overlay-scrim-closed-v1.png"
grep -Fq 'compiler overlay state: v1 entries=1 fixed-alpha-lanes=146 no-packets' /tmp/noir-overlay-x11.log
for action in overlay-open overlay-dismiss overlay-confirm overlay-copy; do
  grep -Fq "event-map dispatch: $action" /tmp/noir-overlay-x11.log
done
grep -Fq 'overlay-state: id=deployment-overlay action=overlay-open visible=true quad-alpha-patches=26 glyph-alpha-patches=120 tile-mask=0x0000000000000001 worklist=no-packets' /tmp/noir-overlay-x11.log
grep -Fq 'overlay-state: id=deployment-overlay action=overlay-dismiss visible=false quad-alpha-patches=26 glyph-alpha-patches=120 tile-mask=0x0000000000000001 worklist=no-packets' /tmp/noir-overlay-x11.log
kill "$host_pid" 2>/dev/null || true
pids=("${pids[@]:0:${#pids[@]}-1}")

expect_rejected initial 'nonbinary initial visibility'
expect_rejected offset 'invalid quad alpha offsets'
expect_rejected tile 'tile ID 1 exceeds compiled tile table'
expect_rejected disable 'may not disable overlay_state_plan v1'
printf '%s\n' 'OVERLAY_STATE_PLAN_V1_REGRESSION: PASS'
