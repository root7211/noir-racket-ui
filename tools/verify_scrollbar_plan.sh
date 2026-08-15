#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
SCENE="$ROOT/out/data-register-table-10000.scene.json"
DISPLAY_ID="${NOIR_SCROLLBAR_DISPLAY:-:110}"
LOG="${NOIR_SCROLLBAR_LOG:-/tmp/noir-scrollbar-plan-x11.log}"

[[ -x "$HOST" ]] || { echo "missing release host: $HOST" >&2; exit 1; }

(
  cd "$ROOT"
  NOIR_ENTRY_MODULE=examples/data-register-table-10000.rkt PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt out/data-register-table-10000.scene.json
) >/tmp/noir-scrollbar-plan-export.log 2>&1

grep -Fq '"schema":"noir-scrollbar-plan-v1"' "$SCENE"
grep -Fq '"abi_schema":"noir-scrollbar-plan-v1"' "$SCENE"
grep -Fq '"id":"telemetry-scrollbar"' "$SCENE"
grep -Fq '"tile_ids":[2]' "$SCENE"
grep -Fq '"thumb_instance_offset":572' "$SCENE"

Xvfb "$DISPLAY_ID" -screen 0 1280x720x24 >/tmp/noir-scrollbar-plan-xvfb.log 2>&1 &
XVFB_PID=$!
HOST_PID=""
cleanup() {
  kill "$HOST_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1

DISPLAY="$DISPLAY_ID" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  "$HOST" "$SCENE" >"$LOG" 2>&1 &
HOST_PID=$!
sleep 3
WINDOW=$(DISPLAY="$DISPLAY_ID" xdotool search --name 'Noir Glyph Atlas host' | head -n1)
[[ -n "$WINDOW" ]]
DISPLAY="$DISPLAY_ID" xdotool windowfocus "$WINDOW"
DISPLAY="$DISPLAY_ID" xdotool getwindowgeometry --shell "$WINDOW" >/tmp/noir-scrollbar-plan-window.sh
# xdotool emits shell-safe X/Y assignments.
source /tmp/noir-scrollbar-plan-window.sh
# Track: x=588..600, y=106..190; y=148 is exactly its geometric midpoint.
DISPLAY="$DISPLAY_ID" xdotool mousemove "$((X + 594))" "$((Y + 115))"
DISPLAY="$DISPLAY_ID" xdotool mousedown 1
DISPLAY="$DISPLAY_ID" xdotool mousemove "$((X + 594))" "$((Y + 148))"
DISPLAY="$DISPLAY_ID" xdotool mouseup 1
sleep 3
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -Fq 'compiler scrollbar: id=telemetry-scrollbar list=telemetry-registers track=12x84+588,106 thumb-height=18 max-viewport=9997 tiles=[2] worklist=2' "$LOG"
grep -Fq 'scrollbar-drag: id=telemetry-scrollbar list=telemetry-registers pointer-y=148.000 viewport=4999 thumb-offset=572 tile-mask=0x0000000000000004 worklist=no-packets changed=true' "$LOG"
grep -Fq 'compact-register scroll: list=telemetry-registers table=telemetry-data capacity=10000 target=4999 row-tiles=[3, 0, 1] physical-slots=4 glyph-id-patches=36 template=ring-v1' "$LOG"
grep -Fq 'scrollbar-thumb-sync: id=telemetry-scrollbar list=telemetry-registers viewport=4999 thumb-offset=572 tile-mask=0x0000000000000004 worklist=no-packets' "$LOG"
grep -Fq 'virtual-list scroll-submit: list=telemetry-registers viewport=4999' "$LOG"

TILE_TAMPER=/tmp/noir-scrollbar-widened-tile.scene.json
SCHEMA_TAMPER=/tmp/noir-scrollbar-schema-v9.scene.json
sed 's/"thumb_instance_offset":572,"tile_ids":\[2\]/"thumb_instance_offset":572,"tile_ids":[1,2]/' "$SCENE" > "$TILE_TAMPER"
sed 's/"abi_schema":"noir-scrollbar-plan-v1"/"abi_schema":"noir-scrollbar-plan-v9"/' "$SCENE" > "$SCHEMA_TAMPER"

expect_reject() {
  local scene="$1" expected="$2" output="$3"
  set +e
  DISPLAY="$DISPLAY_ID" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$HOST" "$scene" >"$output" 2>&1
  local status=$?
  set -e
  [[ "$status" -ne 0 ]]
  grep -Fq "$expected" "$output"
}
expect_reject "$TILE_TAMPER" 'scrollbar telemetry-scrollbar has widened or incorrect compiler tile scope' /tmp/noir-scrollbar-tile-tamper.log
expect_reject "$SCHEMA_TAMPER" 'scrollbar telemetry-scrollbar has unsupported ABI noir-scrollbar-plan-v9@1' /tmp/noir-scrollbar-schema-tamper.log

echo 'PASS: real X11 scrollbar drag used fixed viewport mapping, 4-slot recycling, one thumb pos.y address, no-packets local tile; widened tile and schema drift were rejected'
grep -E 'compiler scrollbar:|scrollbar-drag:.*pointer-y=148|scrollbar-thumb-sync:.*viewport=4999|compact-register scroll:.*target=4999|virtual-list scroll-submit:.*viewport=4999' "$LOG"
