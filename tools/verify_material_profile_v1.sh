#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30
mkdir -p "$OUT"

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f /tmp/noir-material-negative-*.rkt
}
trap cleanup EXIT

compile_negative() {
  local name="$1" expected="$2" source="$3" path
  path="/tmp/noir-material-negative-${name}.rkt"
  printf '%s\n' "$source" > "$path"
  set +e
  PLTCOLLECTS="$ROOT:" racket "$path" > "/tmp/noir-material-negative-${name}.log" 2>&1
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "Material negative fixture ${name} unexpectedly compiled" >&2
    exit 1
  fi
  grep -Fq "$expected" "/tmp/noir-material-negative-${name}.log"
}

start_xvfb() {
  local display="$1" log="$2"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >"$log" 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2
  return 1
}

next_display() {
  local n
  for n in $(seq 330 360); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then
      printf ':%s' "$n"
      return 0
    fi
  done
  return 1
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt > /tmp/noir-material-profile-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-material-profile-racket.log
NOIR_ENTRY_MODULE=examples/material-profile-dashboard.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$OUT/material-profile-dashboard.scene.json"
python3 tools/verify_material_profile_v1.py "$OUT/material-profile-dashboard.scene.json"

compile_negative missing-active 'must name one declared material-destination' '#lang noir/ui
(noir-app
 (material-profile material-dark)
 (state [n 0])
 (stack #:id root #:width 640 #:height 360 #:clip #t #:background (theme-color background)
   (material-nav-rail #:id rail #:active absent #:font-face fake #:x 0 #:y 0 #:width 180 #:height 320
     (material-destination #:id one #:label-id one-label #:label "One")
     (material-destination #:id two #:label-id two-label #:label "Two")
     (material-destination #:id three #:label-id three-label #:label "Three"))))'
compile_negative destination-count 'requires 3 to 7 literal material-destination children' '#lang noir/ui
(noir-app
 (material-profile material-dark)
 (state [n 0])
 (stack #:id root #:width 640 #:height 360 #:clip #t #:background (theme-color background)
   (material-nav-rail #:id rail #:active one #:font-face fake #:x 0 #:y 0 #:width 180 #:height 320
     (material-destination #:id one #:label-id one-label #:label "One")
     (material-destination #:id two #:label-id two-label #:label "Two"))))'
compile_negative mutually-exclusive 'mutually exclusive compile-time token sources' '#lang noir/ui
(noir-app
 (material-profile material-dark)
 (theme conflicting
   (color canvas "#000000" surface "#000000")
   (space sm 4)
   (type body 14)
   (radius card 4))
 (state [n 0])
 (stack #:id root #:width 640 #:height 360 #:clip #t #:background (theme-color background)))'

cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host > /tmp/noir-material-profile-cargo.log 2>&1
DISPLAY="$(next_display)"
start_xvfb "$DISPLAY" /tmp/noir-material-profile-xvfb.log
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$OUT/material-profile-dashboard.scene.json" > /tmp/noir-material-profile-x11.log 2>&1 &
host_pid=$!
pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
DISPLAY="$DISPLAY" xdotool mousemove 1060 560 click 1
sleep 1
DISPLAY="$DISPLAY" xdotool mousemove 1260 700
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-profile-dashboard-v1.png"
grep -Fq 'compiler rounded surfaces: v1' /tmp/noir-material-profile-x11.log
grep -Fq 'event-map dispatch: material-refresh' /tmp/noir-material-profile-x11.log
grep -Fq 'state-slot write: action=material-refresh state=refresh-count index=0 op=add value=1' /tmp/noir-material-profile-x11.log
grep -Fq 'glyph-id-patch material-refresh-count:' /tmp/noir-material-profile-x11.log
printf '%s\n' 'MATERIAL_PROFILE_V1_REGRESSION: PASS'
