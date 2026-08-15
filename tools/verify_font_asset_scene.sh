#!/usr/bin/env bash
# Reproducible v1 font asset Scene/Rust proof regression.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
SCENE="$ROOT/out/log-browser-font.scene.json"
STAGE="$(mktemp -d /tmp/noir-font-asset-v1.XXXXXX)"
DISPLAY_NUM=:119
XVFB=""

cleanup() {
  [[ -n "$XVFB" ]] && kill "$XVFB" 2>/dev/null || true
  rm -rf "$STAGE"
}
trap cleanup EXIT

[[ -x "$BIN" ]] || { echo "missing release host: $BIN" >&2; exit 1; }
cd "$ROOT"

NOIR_ENTRY_MODULE=examples/log-browser.rkt PLTCOLLECTS="$ROOT:" racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-font-asset-export.log 2>&1
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-font-asset-racket.log 2>&1
"$ROOT/tools/verify_fontc_theme.sh" >/tmp/noir-font-asset-fontc-theme.log 2>&1

mkdir -p "$STAGE/out" "$STAGE/assets"
cp "$SCENE" "$STAGE/out/scene.json"
cp -a "$ROOT/assets/fontc" "$STAGE/assets/fontc"

Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 >/tmp/noir-font-asset-xvfb.log 2>&1 &
XVFB=$!
sleep 1

run_host() {
  local scene="$1"
  local log="$2"
  set +e
  timeout 5s env DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" "$scene" >"$log" 2>&1
  local status=$?
  set -e
  [[ "$status" == 0 || "$status" == 124 ]] || return "$status"
}

run_host "$STAGE/out/scene.json" /tmp/noir-font-asset-positive.log
grep -F 'compiler font asset: face=noir-desktop-sans-18 page=2 glyphs=95 atlas=512x512 r8 activation=registered-inactive' /tmp/noir-font-asset-positive.log
grep -F 'font-atlas-upload: face=noir-desktop-sans-18 page=2 bytes=262144 sha256=613ac89f108883cfdff0d3e422a2a265120eb4a1c6099803958a102c0fd6956c renderer=registered-inactive' /tmp/noir-font-asset-positive.log

cp "$STAGE/assets/fontc/noir-desktop-sans-18/atlas.r8" "$STAGE/assets/fontc/noir-desktop-sans-18/atlas.r8.orig"
printf '\377' | dd of="$STAGE/assets/fontc/noir-desktop-sans-18/atlas.r8" bs=1 seek=0 conv=notrunc status=none
set +e
timeout 5s env DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" "$STAGE/out/scene.json" >/tmp/noir-font-asset-atlas-tamper.log 2>&1
TAMPER_STATUS=$?
set -e
[[ "$TAMPER_STATUS" != 0 && "$TAMPER_STATUS" != 124 ]]
grep -F 'atlas SHA-256 mismatch' /tmp/noir-font-asset-atlas-tamper.log
mv "$STAGE/assets/fontc/noir-desktop-sans-18/atlas.r8.orig" "$STAGE/assets/fontc/noir-desktop-sans-18/atlas.r8"

sed 's/"atlas_page":2/"atlas_page":1/' "$STAGE/out/scene.json" > "$STAGE/out/page-conflict.scene.json"
set +e
timeout 5s env DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" "$STAGE/out/page-conflict.scene.json" >/tmp/noir-font-asset-page-tamper.log 2>&1
PAGE_STATUS=$?
set -e
[[ "$PAGE_STATUS" != 0 && "$PAGE_STATUS" != 124 ]]
grep -F 'must own isolated atlas page 2' /tmp/noir-font-asset-page-tamper.log

echo 'font asset Scene v1: positive upload + atlas tamper reject + page conflict reject: PASS'
