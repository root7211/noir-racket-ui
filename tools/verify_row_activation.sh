#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/out/data-register-table-10000.scene.json"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
LOG="${NOIR_ROW_ACTIVATION_LOG:-/tmp/noir-row-activation-integration.log}"
DISPLAY_ID="${NOIR_ROW_ACTIVATION_DISPLAY:-:94}"

if [[ ! -x "$HOST" ]]; then
  echo "missing release host: $HOST" >&2
  exit 1
fi

Xvfb "$DISPLAY_ID" -screen 0 1280x720x24 >/tmp/noir-row-activation-xvfb.log 2>&1 &
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

export DISPLAY="$DISPLAY_ID"
WIN=""
for _ in $(seq 1 40); do
  WIN="$(xdotool search --onlyvisible --name 'Noir Glyph Atlas host' 2>/dev/null | head -n1 || true)"
  [[ -n "$WIN" ]] && break
  sleep 0.25
done
[[ -n "$WIN" ]]

# Row 1 is inside the fixed 572×84 list viewport at the compiler-known local coordinate y=145.
# The release selects logical row 1 and immediately activates its static row_activation_plan.
xdotool mousemove --window "$WIN" 100 145 click 1
sleep 1
# Xvfb defaults focus to root; explicitly focus the winit window before the real Enter event.
xdotool windowfocus "$WIN"
sleep 0.25
xdotool key Return
sleep 3

kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -Fq 'compiler row activation: list=telemetry-registers action=refresh-tick slot=0 batch=coalesced-activate-refresh-registers tile-mask=0x0000000000000001 worklist=2' "$LOG"
grep -Fq 'list-selection: list=telemetry-registers logical=1 physical=1' "$LOG"
[[ "$(grep -Fc 'row-activation: list=telemetry-registers logical=1 physical=1 action-slot=0 batch=coalesced-activate-refresh-registers action-tile-mask=0x0000000000000001 worklist=2' "$LOG")" -eq 2 ]]
[[ "$(grep -Fc 'coalesced-batch execute: coalesced-activate-refresh-registers refs=[Transient(2), Action(0)] worklist_slots=[2, 2]' "$LOG")" -eq 2 ]]
grep -Fq 'state-slot write: action=refresh-tick state=tick index=0 op=add value=1' "$LOG"
grep -Fq 'state-slot write: action=refresh-tick state=tick index=0 op=add value=2' "$LOG"
[[ "$(grep -Fc 'render-request-enqueue coalesced-activate-refresh-registers: mask=0x0000000000000003 strategy=None worklist=2' "$LOG")" -eq 2 ]]
grep -Fq 'packet-activity-skip worklist=no-packets index=2 packets=[] reason=compiler-empty' "$LOG"

echo 'PASS: real X11 row release and Enter both reused row_activation_plan → coalesced batch → no-packets local RenderRequest'
grep -E 'compiler row activation:|list-selection:|row-activation:|coalesced-batch execute: coalesced-activate-refresh-registers|state-slot write: action=refresh-tick|render-request-enqueue coalesced-activate-refresh-registers:' "$LOG"
