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

# Positive path is intentionally the normal Material dashboard regression: it proves
# the fixed shadow pass coexists with rounded surfaces, static page-2 text and action-local glyph patches.
bash "$ROOT/tools/verify_material_profile_v1.sh"

next_display() {
  local n
  for n in $(seq 361 390); do
    if [[ ! -e "/tmp/.X${n}-lock" && ! -S "/tmp/.X11-unix/X${n}" ]]; then
      printf ':%s' "$n"
      return 0
    fi
  done
  return 1
}

DISPLAY="$(next_display)"
Xvfb "$DISPLAY" -screen 0 1280x720x24 -nolisten tcp > /tmp/noir-shadow-xvfb.log 2>&1 &
xvfb_pid=$!
cleanup() { kill "$xvfb_pid" 2>/dev/null || true; }
trap cleanup EXIT
for _ in $(seq 1 30); do [[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]] && break; sleep 0.1; done
[[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]]

scene="$OUT/material-profile-dashboard.scene.json"
for mode in blur offset geometry disable; do
  attack="$OUT/material-profile-shadow-attack-${mode}.scene.json"
  python3 "$ROOT/tools/mutate_shadow_surface_scene.py" "$scene" "$mode" "$attack" > "/tmp/noir-shadow-mutate-${mode}.log"
  set +e
  DISPLAY="$DISPLAY" WGPU_BACKEND=vulkan "$BIN" "$attack" > "/tmp/noir-shadow-attack-${mode}.log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "shadow attack ${mode} unexpectedly passed" >&2
    exit 1
  fi
  case "$mode" in
    blur|geometry) grep -Fq 'geometry/recipe disagrees with compiler layout' "/tmp/noir-shadow-attack-${mode}.log" ;;
    offset) grep -Fq 'source/elevation/instance offset disagrees with frozen layout' "/tmp/noir-shadow-attack-${mode}.log" ;;
    disable) grep -Fq 'desktop-wide visual Scene may not disable shadow_surface_plan v1' "/tmp/noir-shadow-attack-${mode}.log" ;;
  esac
done

grep -Fq 'compiler shadow surfaces: v1 layers=6 elevated-sources=3 immutable-shadow-instances=1pass' /tmp/noir-material-profile-x11.log
printf '%s\n' 'SHADOW_SURFACE_PLAN_V1_REGRESSION: PASS'
