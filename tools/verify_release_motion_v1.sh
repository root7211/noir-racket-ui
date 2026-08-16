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
  rm -f "$OUT"/material-overlay-release-motion-attack-*.scene.json
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 461 480); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then printf ':%s' "$n"; return 0; fi
  done
  return 1
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-release-motion-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-release-motion-racket.log
NOIR_ENTRY_MODULE=examples/material-overlay-showcase.rkt PLTCOLLECTS="$ROOT:" racket tools/export-dashboard.rkt "$SCENE"
python3 tools/verify_release_motion_v1.py "$SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-release-motion-cargo.log 2>&1

DISPLAY="$(next_display)"
Xvfb "$DISPLAY" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-release-motion-xvfb.log 2>&1 &
pids+=("$!")
for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]] && break; sleep 0.1; done
[[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]]

for mode in duration offset damage drop; do
  attack="$OUT/material-overlay-release-motion-attack-$mode.scene.json"
  python3 tools/mutate_release_motion_scene.py "$mode" "$SCENE" "$attack" >/tmp/noir-release-motion-$mode-mutate.log
  set +e
  timeout 8s env WGPU_BACKEND=vulkan DISPLAY="$DISPLAY" "$BIN" "$attack" >/tmp/noir-release-motion-$mode-host.log 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 && "$status" -ne 124 ]]
  grep -Eq 'release motion.*(canonical|offsets|damage|count)|release motion track count' "/tmp/noir-release-motion-$mode-host.log"
  printf 'release motion attack %s: REJECTED\n' "$mode"
done

DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-release-motion-host.log 2>&1 &
host=$!
pids+=("$host")
sleep 3
kill -0 "$host"
# deployment-confirm is a compiler-fixed x=760..864/y=396..436 event rectangle.
DISPLAY="$DISPLAY" xdotool mousemove 812 416 mousedown 1
sleep 0.12
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-motion-pressed-v1.png"
DISPLAY="$DISPLAY" xdotool mouseup 1
sleep 0.25
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-motion-rest-v1.png"
grep -Fq 'compiler release motion: tracks=5 recipe=80ms-ease-out fixed-fields=pos+color' /tmp/noir-release-motion-host.log
grep -Fq 'release-motion start: id=release-deployment-confirm event-slot=1 duration-ms=80' /tmp/noir-release-motion-host.log
grep -Fq 'release-motion complete: id=release-deployment-confirm event-slot=1 frames=bounded' /tmp/noir-release-motion-host.log
grep -Fq 'event-map dispatch: overlay-confirm' /tmp/noir-release-motion-host.log
grep -Fq 'glyph-id-patch overlay-count:' /tmp/noir-release-motion-host.log
printf '%s\n' 'RELEASE_MOTION_V1_REGRESSION: PASS'
