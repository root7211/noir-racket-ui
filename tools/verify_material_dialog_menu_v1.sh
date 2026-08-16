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
tmp=''
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  [[ -n "$tmp" ]] && rm -rf "$tmp"
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 401 420); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then
      printf ':%s' "$n"
      return 0
    fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-dialog-menu-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2
  return 1
}

expect_macro_rejected() {
  local name="$1" needle="$2" source="$3" path
  path="$tmp/${name}.rkt"
  printf '%s\n' "$source" >"$path"
  set +e
  PLTCOLLECTS="$ROOT:" racket "$path" >"$tmp/${name}.log" 2>&1
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "macro fixture $name was unexpectedly accepted" >&2
    return 1
  fi
  grep -Fq "$needle" "$tmp/${name}.log"
  printf 'dialog/menu macro fixture %s: REJECTED\n' "$name"
}

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-dialog-menu-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-dialog-menu-racket.log
NOIR_ENTRY_MODULE=examples/material-overlay-showcase.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$SCENE"
python3 tools/verify_material_overlay_v1.py "$SCENE"

# Macro failures must occur at expansion, before a Scene or GPU resource exists.
tmp="$(mktemp -d /tmp/noir-dialog-menu-v1.XXXXXX)"
expect_macro_rejected menu-count 'requires 2 to 6 literal material-menu-item children' '#lang noir/ui
(noir-app (material-profile material-dark) (state [n 0]) (action tick (set n (+ n 1)))
  (stack #:id root #:width 1216 #:height 656 #:background (theme-color background)
    (material-menu #:id menu #:font-face noir-desktop-sans-18 #:x 20 #:y 20 #:width 240 #:height 120
      (material-menu-item #:id only #:label-id only-label #:label "Only" #:on tick))))'
expect_macro_rejected dialog-geometry 'requires fixed width >= 280px and height >= 180px' '#lang noir/ui
(noir-app (material-profile material-dark) (state [n 0]) (action tick (set n (+ n 1)))
  (stack #:id root #:width 1216 #:height 656 #:background (theme-color background)
    (material-dialog #:id dialog #:scrim-id scrim #:title-id title #:body-id body #:confirm-id confirm #:dismiss-id dismiss
      #:title "Title" #:body "Body" #:confirm-label "Yes" #:dismiss-label "No" #:font-face noir-desktop-sans-18
      #:confirm-on tick #:dismiss-on tick #:x 40 #:y 40 #:width 240 #:height 180)))'

cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-dialog-menu-cargo.log 2>&1
DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-dialog-menu-x11.log 2>&1 &
host_pid=$!
pids+=("$host_pid")
sleep 3
kill -0 "$host_pid"
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-overlay-showcase-v1.png"
# The scene fixes confirm at x=760..864, y=396..436 and Copy artifact at x=936..1144, y=216..256.
DISPLAY="$DISPLAY" xdotool mousemove 812 416 click 1
sleep 0.6
DISPLAY="$DISPLAY" xdotool mousemove 1000 236 click 1
sleep 0.8
DISPLAY="$DISPLAY" xdotool mousemove 1260 700
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-overlay-showcase-actions-v1.png"
grep -Fq 'compiler navigation selection: disabled destinations=0' /tmp/noir-dialog-menu-x11.log
grep -Fq 'compiler shadow surfaces: v1 layers=6 elevated-sources=3' /tmp/noir-dialog-menu-x11.log
grep -Fq 'event-map dispatch: overlay-confirm' /tmp/noir-dialog-menu-x11.log
grep -Fq 'event-map dispatch: overlay-copy' /tmp/noir-dialog-menu-x11.log
grep -Fq 'state-slot write: action=overlay-confirm state=overlay-count index=0 op=add value=1' /tmp/noir-dialog-menu-x11.log
grep -Fq 'state-slot write: action=overlay-copy state=overlay-count index=0 op=add value=2' /tmp/noir-dialog-menu-x11.log
kill "$host_pid" 2>/dev/null || true
pids=(${pids[@]:0:${#pids[@]}-1})
printf '%s\n' 'MATERIAL_DIALOG_MENU_V1_REGRESSION: PASS'
