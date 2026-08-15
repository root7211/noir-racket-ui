#!/usr/bin/env bash
# Real X11/Vulkan oracle for the static multi-field-event DSL fixture.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENE="$ROOT/out/composite-worklist-dashboard.scene.json"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
LOG="$ROOT/wgpu-verify/out/multifield-event-fusion-e2e.log"
DISPLAY_NUM=:119

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/composite-worklist-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

jq -e '
  ([.event_map[] | select(.node == "fuse-commit") | .transaction_index] == [0]) and
  ([.event_map[] | select(.node == "fuse-reset") | .transaction_index] == [0]) and
  ([.frame_coalesced_batches[] | select(.id == "coalesced-activate-fuse-commit") | .batch_fusion_proof.member_worklist_indices] == [[3,4,5]]) and
  ([.frame_coalesced_batches[] | select(.id == "coalesced-activate-fuse-commit") | .batch_fusion_proof.fused_worklist_index] == [7]) and
  ([.frame_coalesced_batches[] | select(.id == "coalesced-activate-fuse-reset") | .batch_fusion_proof.fused_worklist_index] == [8])
' "$SCENE" >/dev/null

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-multifield-fusion-xvfb.log 2>&1 &
XVFB_PID=$!
HOST_PID=""
cleanup() {
  [[ -n "$HOST_PID" ]] && kill "$HOST_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1
DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan stdbuf -oL "$HOST" "$SCENE" >"$LOG" 2>&1 &
HOST_PID=$!
for _ in $(seq 1 30); do
  WINDOW_ID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' 2>/dev/null | head -n1 || true)
  [[ -n "$WINDOW_ID" ]] && break
  sleep .1
done
[[ -n "${WINDOW_ID:-}" ]]

# Event Map fixes both button rectangles: commit [46,226)x[344,356), reset [320,500)x[344,356).
DISPLAY="$DISPLAY_NUM" xdotool mousemove --window "$WINDOW_ID" 100 350
sleep .1
DISPLAY="$DISPLAY_NUM" xdotool click 1
sleep .3
DISPLAY="$DISPLAY_NUM" xdotool mousemove --window "$WINDOW_ID" 370 350
sleep .1
DISPLAY="$DISPLAY_NUM" xdotool click 1
sleep .3
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -q 'coalesced-batch composite-worklist: batch=coalesced-activate-fuse-commit slot=7 members=\[3, 4, 5\] packets=\[3, 6, 9\]' "$LOG"
grep -q 'render-request-enqueue coalesced-activate-fuse-commit: .*worklist=7' "$LOG"
grep -q 'packet-activity-dispatch worklist=batch-coalesced-activate-fuse-commit index=7 packets=\[3, 6, 9\] workgroups=3' "$LOG"
grep -q 'coalesced-batch composite-worklist: batch=coalesced-activate-fuse-reset slot=8 members=\[3, 4, 5\] packets=\[3, 6, 9\]' "$LOG"
grep -q 'render-request-enqueue coalesced-activate-fuse-reset: .*worklist=8' "$LOG"
grep -q 'packet-activity-dispatch worklist=batch-coalesced-activate-fuse-reset index=8 packets=\[3, 6, 9\] workgroups=3' "$LOG"
printf 'Noir static multi-field event batch-fusion X11/Vulkan verification passed.\n'
