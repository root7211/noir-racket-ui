#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/out/recycling-list-dashboard.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/recycling-list-dashboard.rkt" racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-recycling-export.log 2>&1
jq -e '.virtual_list_plans[0] | .recycling == true and .logical_capacity == 12 and .physical_slots == 4 and (.logical_data_ids | length) == 12 and (.scroll_transitions | length) == 18 and (.scroll_transitions[0].glyph_id_patches | length) == 36 and ([.scroll_transitions[] | select(.to_slot == 4 and .from_slot == 3) | .visible_row_tile_ids] == [[0,1,2]])' "$SCENE" >/dev/null
Xvfb :81 -screen 0 1280x720x24 >/tmp/noir-recycling-oracle-xvfb.log 2>&1 &
XVFB_PID=$!
trap 'kill "$HOST_PID" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true' EXIT
sleep 1
DISPLAY=:81 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-recycling-oracle.log 2>&1 &
HOST_PID=$!
sleep 3
WINDOW_ID=$(DISPLAY=:81 xdotool search --onlyvisible --name '.*' | tail -n 1)
for _ in $(seq 1 6); do DISPLAY=:81 xdotool mousemove --window "$WINDOW_ID" 300 180 click 5; done
sleep 1
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
grep -q 'virtual-list scroll: list=telemetry-ring from=3 to=4 row-tiles=\[0, 1, 2\] instance-patches=8 glyph-patches=36 glyph-id-patches=36 recycling=true' /tmp/noir-recycling-oracle.log
grep -q 'virtual-list scroll-submit: list=telemetry-ring viewport=4.*quad-ranges=3 quad-instances=6 glyph-subranges=3 glyph-placements=27 worklist=no-packets' /tmp/noir-recycling-oracle.log
BAD=/tmp/noir-recycling-tampered.scene.json
jq '(.virtual_list_plans[0].scroll_transitions[0].glyph_id_patches[0].glyph_id) = 65537' "$SCENE" > "$BAD"
set +e
DISPLAY=:81 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan timeout 7s "$BIN" "$BAD" >/tmp/noir-recycling-tampered.log 2>&1
STATUS=$?
set -e
grep -q 'invalid glyph data-binding patch proof' /tmp/noir-recycling-tampered.log
printf '%s\n' 'row recycling oracle: PASS (logical=12, physical=4, 18 transitions, 36 fixed glyph-ID patches per edge, ring wrap and tampered proof rejection verified)'
