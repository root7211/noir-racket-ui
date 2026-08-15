#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
SCENE="${1:-$ROOT/out/registry-match.scene.json}"
LOG="$ROOT/wgpu-verify/out/winit-host-e2e.log"

Xvfb :99 -screen 0 800x600x24 >/tmp/noir-xvfb.log 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 30); do
  xdpyinfo -display :99 >/dev/null 2>&1 && break
  sleep 0.1
done
xdpyinfo -display :99 >/dev/null
HOST_PID=""
cleanup() {
  [ -n "$HOST_PID" ] && kill "$HOST_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT

export DISPLAY=:99
export XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime
export WGPU_BACKEND=vulkan
"$HOST" "$SCENE" >"$LOG" 2>&1 &
HOST_PID=$!

for _ in $(seq 1 30); do
  WINDOW_ID="$(xdotool search --name 'Noir Glyph Atlas host' 2>/dev/null | head -1 || true)"
  [ -n "$WINDOW_ID" ] && break
  sleep 0.1
done
[ -n "${WINDOW_ID:-}" ]

# Fixed coordinates are emitted by the compiler Event Map.
click_at() {
  xdotool mousemove --window "$WINDOW_ID" "$1" 250
  sleep 0.1
  xdotool mousedown 1
  sleep 0.1
  xdotool mouseup 1
  sleep 0.2
}
click_at 100  # refresh-fps
click_at 280  # refresh-latency
click_at 500  # advance-progress
sleep 0.5

# Startup ABI and GPU contract.
grep -q 'compiler action slots: 3 fixed action address(es), lexical ABI' "$LOG"
grep -q 'compiler state slots: 3 fixed value address(es), lexical ABI' "$LOG"
grep -q 'compiler frame coalescing: 6 verified batch(es), 3 event batch pair(s)' "$LOG"
grep -q 'packet-activity-differential: selected=Scalar reference=Scalar packets=2 activity+indirect=equal' "$LOG"

# Transient hover/press/release must carry no-packets explicitly, never via Host state.
grep -q 'render-request-enqueue hover: .*worklist=2' "$LOG"
grep -q 'coalesced-batch execute: coalesced-press-refresh-fps-button .*worklist_slots=\[2, 2\]' "$LOG"
grep -q 'render-request-enqueue coalesced-press-refresh-fps-button: .*worklist=2' "$LOG"
grep -q 'packet-activity-skip worklist=no-packets index=2 packets=\[\] reason=compiler-empty' "$LOG"

# Every activated action batch forwards its task-local compiler slot to RenderRequest.
grep -q 'coalesced-batch execute: coalesced-activate-refresh-fps-button .*worklist_slots=\[2, 2\]' "$LOG"
grep -q 'compiler strategy dispatch: batch=coalesced-activate-refresh-fps-button strategy=coalesced worklist=2' "$LOG"
grep -q 'render-request-enqueue coalesced-activate-refresh-fps-button: mask=0x0000000000000009 strategy=Some(Coalesced) worklist=2' "$LOG"
grep -q 'glyph-id-patch fps: \[800..804), \[832..836), \[864..868) (12 bytes)' "$LOG"
grep -q 'coalesced-batch execute: coalesced-activate-refresh-latency-button .*worklist_slots=\[2, 2\]' "$LOG"
grep -q 'render-request-enqueue coalesced-activate-refresh-latency-button: mask=0x0000000000000012 strategy=Some(Coalesced) worklist=2' "$LOG"
grep -q 'glyph-id-patch latency: \[896..900), \[928..932), \[960..964) (12 bytes)' "$LOG"
grep -q 'coalesced-batch execute: coalesced-activate-advance-progress-button .*worklist_slots=\[2, 2\]' "$LOG"
grep -q 'render-request-enqueue coalesced-activate-advance-progress-button: mask=0x0000000000000024 strategy=Some(Coalesced) worklist=2' "$LOG"
grep -q 'instance-patch throughput state=progress state_index=2: \[316..320)' "$LOG"

# The compatibility fields are absent from the compiled source; all renderer submissions use RenderRequest.
! grep -q -E 'pending_packet_worklist|pending_strategy|\bdirty_tiles\b' "$ROOT/wgpu-verify/src/bin/noir_winit_host.rs"

echo 'winit host RenderRequest queue: explicit tile-mask/strategy/worklist dataflow verified.'
