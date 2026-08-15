#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/out/virtual-list-dashboard.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/virtual-list-dashboard.rkt" racket tools/export-dashboard.rkt "$SCENE" >/tmp/noir-virtual-list-scroll-export.log 2>&1
jq -e '.virtual_list_plans[0] | (.scroll_transitions | length) == 10 and .scroll_transitions[0].from_slot == 0 and .scroll_transitions[0].to_slot == 1 and .scroll_transitions[0].visible_row_tile_ids == [1,2,3] and (.scroll_transitions[0].instance_y_patches | length) == 8 and (.scroll_transitions[0].glyph_y_patches | length) == 32 and (.row_draw_ranges | length) == 8 and (.row_draw_ranges[0] == {first:4,count:2}) and (.row_glyph_subranges[0] == {first:20,count:8})' "$SCENE" >/dev/null
Xvfb :86 -screen 0 1280x720x24 >/tmp/noir-virtual-list-scroll-xvfb.log 2>&1 &
XVFB_PID=$!
trap 'kill "$HOST_PID" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true' EXIT
sleep 1
DISPLAY=:86 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$BIN" "$SCENE" >/tmp/noir-virtual-list-scroll-x11.log 2>&1 &
HOST_PID=$!
sleep 3
WINDOW_ID=$(DISPLAY=:86 xdotool search --onlyvisible --name '.*' | tail -n 1)
DISPLAY=:86 xdotool mousemove --window "$WINDOW_ID" 300 180 click 5
sleep 1
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
grep -q 'virtual-list scroll: list=telemetry-list from=0 to=1 row-tiles=\[1, 2, 3\] instance-patches=8 glyph-patches=32' /tmp/noir-virtual-list-scroll-x11.log
grep -q 'virtual-list scroll-submit: list=telemetry-list viewport=1 scissor=572x84+34,144 quad-ranges=3 quad-instances=6 glyph-subranges=3 glyph-placements=24 worklist=no-packets' /tmp/noir-virtual-list-scroll-x11.log
grep -q 'packet-activity-skip worklist=no-packets index=2 packets=\[\] reason=compiler-empty' /tmp/noir-virtual-list-scroll-x11.log
BAD=/tmp/noir-virtual-list-scroll-tampered.scene.json
jq '(.virtual_list_plans[0].scroll_transitions[0].visible_row_tile_ids[0]) = 0' "$SCENE" > "$BAD"
set +e
DISPLAY=:86 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan timeout 6s "$BIN" "$BAD" >/tmp/noir-virtual-list-scroll-tampered.log 2>&1
STATUS=$?
set -e
grep -q 'widened or incorrect row-tile range' /tmp/noir-virtual-list-scroll-tampered.log
printf '%s\n' 'virtual-list scroll oracle: PASS (10 compiler transitions; X11 wheel uses 8 instance + 32 glyph patches and submits 3 row ranges / 3 glyph subranges; tampered proof rejected)'
