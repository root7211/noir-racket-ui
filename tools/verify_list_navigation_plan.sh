#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
SCENE="$ROOT/out/data-register-table-10000.scene.json"
DISPLAY_ID="${NOIR_LIST_NAVIGATION_DISPLAY:-:116}"
LOG="${NOIR_LIST_NAVIGATION_LOG:-/tmp/noir-list-navigation-plan-x11.log}"

[[ -x "$HOST" ]] || { echo "missing release host: $HOST" >&2; exit 1; }
(
  cd "$ROOT"
  NOIR_ENTRY_MODULE=examples/data-register-table-10000.rkt PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt out/data-register-table-10000.scene.json
) >/tmp/noir-list-navigation-plan-export.log 2>&1

grep -Fq '"schema":"noir-list-navigation-plan-v1"' "$SCENE"
grep -Fq '"abi_schema":"noir-list-navigation-plan-v1"' "$SCENE"
grep -Fq '"id":"telemetry-navigation"' "$SCENE"
grep -Fq '"page_step":3' "$SCENE"
grep -Fq '"max_viewport":9997' "$SCENE"
grep -Fq '"key":"page-up"' "$SCENE"
grep -Fq '"key":"page-down"' "$SCENE"
grep -Fq '"key":"home"' "$SCENE"
grep -Fq '"key":"end"' "$SCENE"

Xvfb "$DISPLAY_ID" -screen 0 1280x720x24 >/tmp/noir-list-navigation-plan-xvfb.log 2>&1 &
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
DISPLAY="$DISPLAY_ID" xdotool key End
DISPLAY="$DISPLAY_ID" xdotool key Page_Up
DISPLAY="$DISPLAY_ID" xdotool key Page_Down
DISPLAY="$DISPLAY_ID" xdotool key Home
sleep 3
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -Fq 'compiler list navigation: id=telemetry-navigation list=telemetry-registers scrollbar=telemetry-scrollbar page-step=3 max-viewport=9997 tiles=[2] worklist=2' "$LOG"
grep -Fq 'list-navigation-plan: id=telemetry-navigation key=End list=telemetry-registers from=0 to=9997 page-step=3 tile-mask=0x0000000000000004 worklist=no-packets' "$LOG"
grep -Fq 'list-navigation-plan: id=telemetry-navigation key=PageUp list=telemetry-registers from=9997 to=9994 page-step=3 tile-mask=0x0000000000000004 worklist=no-packets' "$LOG"
grep -Fq 'list-navigation-plan: id=telemetry-navigation key=PageDown list=telemetry-registers from=9994 to=9997 page-step=3 tile-mask=0x0000000000000004 worklist=no-packets' "$LOG"
grep -Fq 'list-navigation-plan: id=telemetry-navigation key=Home list=telemetry-registers from=9997 to=0 page-step=3 tile-mask=0x0000000000000004 worklist=no-packets' "$LOG"
grep -Fq 'scrollbar-thumb-sync: id=telemetry-scrollbar list=telemetry-registers viewport=9997 thumb-offset=572 tile-mask=0x0000000000000004 worklist=no-packets' "$LOG"
grep -Fq 'scrollbar-thumb-sync: id=telemetry-scrollbar list=telemetry-registers viewport=0 thumb-offset=572 tile-mask=0x0000000000000004 worklist=no-packets' "$LOG"
grep -Fq 'virtual-list scroll-submit: list=telemetry-registers viewport=9997' "$LOG"
grep -Fq 'virtual-list scroll-submit: list=telemetry-registers viewport=0' "$LOG"

TRANSITION_TAMPER=/tmp/noir-list-navigation-transition-tamper.scene.json
TILE_TAMPER=/tmp/noir-list-navigation-tile-tamper.scene.json
sed 's/"kind":"subtract-step"/"kind":"add-step-clamp"/' "$SCENE" > "$TRANSITION_TAMPER"
sed 's/"tile_ids":\[2\],"transitions":/"tile_ids":[1,2],"transitions":/' "$SCENE" > "$TILE_TAMPER"
expect_reject() {
  local scene="$1" expected="$2" output="$3"
  set +e
  DISPLAY="$DISPLAY_ID" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$HOST" "$scene" >"$output" 2>&1
  local status=$?
  set -e
  [[ "$status" -ne 0 ]]
  grep -Fq "$expected" "$output"
}
expect_reject "$TRANSITION_TAMPER" 'list navigation telemetry-navigation transition table is not canonical PageUp/PageDown/Home/End' /tmp/noir-list-navigation-transition-tamper.log
expect_reject "$TILE_TAMPER" 'list navigation telemetry-navigation disagrees with bound scrollbar tile scope' /tmp/noir-list-navigation-tile-tamper.log

echo 'PASS: real X11 End/PageUp/PageDown/Home used the compiler-fixed viewport transitions, 4-slot recycling, scrollbar thumb sync and no-packets local render; transition and tile drift were rejected'
grep -E 'compiler list navigation:|list-navigation-plan:|scrollbar-thumb-sync:.*viewport=(9997|0)' "$LOG"
