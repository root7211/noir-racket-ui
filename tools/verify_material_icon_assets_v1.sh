#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SPEC="$ROOT/assets/fontc/noir-desktop-sans-18.spec.json"
SCENE="$OUT/material-profile-dashboard.scene.json"
OVERLAY_SCENE="$OUT/material-overlay-showcase.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30
mkdir -p "$OUT"

tmp="$(mktemp -d /tmp/noir-icon-assets-v1.XXXXXX)"
pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$tmp"
}
trap cleanup EXIT

next_display() {
  local n
  for n in $(seq 431 450); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then printf ':%s' "$n"; return 0; fi
  done
  return 1
}

start_xvfb() {
  local display="$1"
  Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-icon-assets-xvfb.log 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${display#:}" ]] && return 0; sleep 0.1; done
  echo "Xvfb did not become ready" >&2
  return 1
}

expect_bad_icon_rejected() {
  cat >"$tmp/bad-icon.rkt" <<'RKT'
#lang noir/ui
(noir-app
 (font-asset #:manifest "assets/fontc/noir-desktop-sans-18/manifest.json"
             #:atlas "assets/fontc/noir-desktop-sans-18/atlas.r8")
 (visual-preset desktop-wide)
 (material-profile material-dark)
 (state [n 0])
 (action tick (set n (+ n 1)))
 (stack #:id root #:width 1216 #:height 656 #:background (theme-color background)
   (material-icon #:id unsupported #:name rocket #:font-face noir-desktop-sans-18 #:x 20 #:y 20)))
RKT
  set +e
  (cd "$ROOT" && PLTCOLLECTS="$ROOT:" racket "$tmp/bad-icon.rkt") >"$tmp/bad-icon.log" 2>&1
  local status=$?
  set -e
  [[ "$status" -ne 0 ]]
  grep -Fq 'unknown icon rocket' "$tmp/bad-icon.log"
  printf '%s\n' 'icon macro fixture unsupported-name: REJECTED'
}

cd "$ROOT"
python3 tools/noir_fontc.py "$SPEC" --out "$tmp/a" >/tmp/noir-icon-fontc-a.json
python3 tools/noir_fontc.py "$SPEC" --out "$tmp/b" >/tmp/noir-icon-fontc-b.json
cmp "$tmp/a/atlas.r8" "$tmp/b/atlas.r8"
cmp "$tmp/a/manifest.json" "$tmp/b/manifest.json"
python3 - "$tmp/a/manifest.json" <<'PY'
import json, sys
m=json.load(open(sys.argv[1]))
assert m['coverage_policy'] == 'ascii-printable+icon-v1'
assert m['glyph_count'] == 102
assert ''.join(m['icon_domain']) == '⌂▣◉⋮×+◆↗'
assert [g['glyph_id'] for g in m['glyphs'] if g['codepoint'] < 127] == list(range(95))
print('ICON_FONTC_DETERMINISM: PASS glyphs=102 icon-domain=8 ascii-ids-stable=95')
PY
expect_bad_icon_rejected
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-icon-assets-racket.log 2>&1
grep -Fq 'Noir Cost Model language checks passed' /tmp/noir-icon-assets-racket.log
NOIR_ENTRY_MODULE=examples/material-profile-dashboard.rkt PLTCOLLECTS="$ROOT:" racket tools/export-dashboard.rkt "$SCENE"
NOIR_ENTRY_MODULE=examples/material-overlay-showcase.rkt PLTCOLLECTS="$ROOT:" racket tools/export-dashboard.rkt "$OVERLAY_SCENE"
python3 tools/verify_material_profile_v1.py "$SCENE"
python3 tools/verify_material_overlay_v1.py "$OVERLAY_SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-icon-assets-cargo.log 2>&1
DISPLAY="$(next_display)"
start_xvfb "$DISPLAY"
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-icon-assets-profile.log 2>&1 &
profile_pid=$!
pids+=("$profile_pid")
sleep 3
kill -0 "$profile_pid"
# Systems target has a fixed hit rect x=44..200, y=120..168 in the desktop frame.
DISPLAY="$DISPLAY" xdotool mousemove 100 152 click 1
sleep 0.8
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-profile-icons-systems-v1.png"
grep -Fq 'compiler font asset: face=noir-desktop-sans-18 page=2 glyphs=102' /tmp/noir-icon-assets-profile.log
grep -Fq 'compiler font placement proof: active-page2-glyphs=224' /tmp/noir-icon-assets-profile.log
grep -Fq 'event-map dispatch: material-select-systems' /tmp/noir-icon-assets-profile.log
kill "$profile_pid" 2>/dev/null || true
pids=(${pids[@]:0:${#pids[@]}-1})
DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$OVERLAY_SCENE" >/tmp/noir-icon-assets-overlay.log 2>&1 &
overlay_pid=$!
pids+=("$overlay_pid")
sleep 3
kill -0 "$overlay_pid"
# Copy artifact target is fixed at x=936..1144, y=216..256.
DISPLAY="$DISPLAY" xdotool mousemove 1000 236 click 1
sleep 0.7
DISPLAY="$DISPLAY" ffmpeg -y -loglevel error -video_size 1280x720 -f x11grab -i "${DISPLAY}.0" -frames:v 1 "$OUT/material-overlay-showcase-icons-actions-v1.png"
grep -Fq 'compiler font placement proof: active-page2-glyphs=228' /tmp/noir-icon-assets-overlay.log
grep -Fq 'event-map dispatch: overlay-copy' /tmp/noir-icon-assets-overlay.log
grep -Fq 'state-slot write: action=overlay-copy state=overlay-count index=0 op=add value=1' /tmp/noir-icon-assets-overlay.log
kill "$overlay_pid" 2>/dev/null || true
pids=(${pids[@]:0:${#pids[@]}-1})
printf '%s\n' 'MATERIAL_ICON_ASSETS_V1_REGRESSION: PASS'
