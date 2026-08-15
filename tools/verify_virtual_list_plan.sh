#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/out/virtual-list-dashboard.scene.json"
BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
LOG="$ROOT/wgpu-verify/out/virtual-list-x11.log"
REPORT="$ROOT/wgpu-verify/out/virtual-list-benchmark.json"
DISPLAY_NUM=:97

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/virtual-list-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE" >/dev/null

jq -e '
  .virtual_list_plans == [{
    id: "telemetry-list",
    capacity: 8,
    visible_rows: 3,
    row_height: 28,
    viewport_height: 84,
    visible_row_tile_ids: [0, 1, 2],
    row_ids: ["node-aa", "node-bb", "node-cc", "node-dd", "node-ee", "node-ff", "node-gg", "node-hh"],
    row_layout_offsets: [176, 264, 352, 440, 528, 616, 704, 792]
  }]
' "$SCENE" >/dev/null

Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-virtual-list-xvfb.log 2>&1 &
XVFB_PID=$!
trap 'kill "$XVFB_PID" 2>/dev/null || true' EXIT
sleep 1
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  "$BIN" "$SCENE" --benchmark-report "$REPORT" >"$LOG" 2>&1

grep -q 'compiler virtual lists: telemetry-list capacity=8 viewport=3x28 row-tiles=\[0, 1, 2\]' "$LOG"
grep -q 'packet-activity-differential: selected=Scalar reference=Scalar' "$LOG"
grep -q 'benchmark report:' "$LOG"

echo 'virtual-list-plan oracle: PASS (capacity=8, viewport=3×28, row-tile=[0,1,2], X11/Vulkan proof accepted)'
