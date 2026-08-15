#!/usr/bin/env bash
# Real X11/Vulkan oracle for compiler-proved composite worklists.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENE="$ROOT/out/settings-dashboard.scene.json"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
LOG="$ROOT/wgpu-verify/out/composite-worklist-e2e.log"
DISPLAY_NUM=:118

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/settings-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

# Compile-time artifact: two transaction button batches each own an exact 3-field union.
jq -e '
  ([.packet_worklists[] | select(.id == "batch-coalesced-activate-apply-all-button") | .packet_indices] == [[3,6,9]]) and
  ([.packet_worklists[] | select(.id == "batch-coalesced-activate-reset-all-button") | .packet_indices] == [[3,6,9]]) and
  ([.frame_coalesced_batches[] | select(.id == "coalesced-activate-apply-all-button") | .composite_worklist_member_indices] == [[3,4,5]]) and
  ([.frame_coalesced_batches[] | select(.id == "coalesced-activate-apply-all-button") | .composite_worklist_index] == [7]) and
  ([.frame_coalesced_batches[] | select(.id == "coalesced-activate-reset-all-button") | .composite_worklist_member_indices] == [[3,4,5]]) and
  ([.frame_coalesced_batches[] | select(.id == "coalesced-activate-reset-all-button") | .composite_worklist_index] == [8])
' "$SCENE" >/dev/null

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-composite-worklist-xvfb.log 2>&1 &
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

# Coordinates come from the compiler Event Map: Apply All=[46..226)x[344..356), Reset=[320..500)x[344..356).
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

# Runtime must consume the batch-local slots, not last task-local slots or transaction slot 6.
grep -q 'coalesced-batch composite-worklist: batch=coalesced-activate-apply-all-button slot=7 members=\[3, 4, 5\] packets=\[3, 6, 9\]' "$LOG"
grep -q 'render-request-enqueue coalesced-activate-apply-all-button: .*worklist=7' "$LOG"
grep -q 'packet-activity-dispatch worklist=batch-coalesced-activate-apply-all-button index=7 packets=\[3, 6, 9\] workgroups=3' "$LOG"
grep -q 'coalesced-batch composite-worklist: batch=coalesced-activate-reset-all-button slot=8 members=\[3, 4, 5\] packets=\[3, 6, 9\]' "$LOG"
grep -q 'render-request-enqueue coalesced-activate-reset-all-button: .*worklist=8' "$LOG"
grep -q 'packet-activity-dispatch worklist=batch-coalesced-activate-reset-all-button index=8 packets=\[3, 6, 9\] workgroups=3' "$LOG"

printf 'Noir compiler-proved composite worklist X11/Vulkan verification passed.\n'
