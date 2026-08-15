#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/out/data-register-table-10000.scene.json"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
LOG="${NOIR_LIST_INTERACTION_LOG:-/tmp/noir-list-interaction-integration.log}"
DISPLAY_ID="${NOIR_LIST_INTERACTION_DISPLAY:-:90}"

if [[ ! -x "$HOST" ]]; then
  echo "missing release host: $HOST" >&2
  exit 1
fi

Xvfb "$DISPLAY_ID" -screen 0 1280x720x24 >/tmp/noir-list-interaction-xvfb.log 2>&1 &
XVFB_PID=$!
HOST_PID=""
cleanup() {
  kill "$HOST_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1

DISPLAY="$DISPLAY_ID" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  "$HOST" "$SCENE" --inject-list-release telemetry-registers 1 >"$LOG" 2>&1 &
HOST_PID=$!
sleep 4

export DISPLAY="$DISPLAY_ID"
WIN="$(xdotool search --name 'Noir Glyph Atlas host' | head -n1)"
xdotool windowfocus "$WIN" || true
xdotool key --window "$WIN" Down Down
sleep 1
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

grep -q 'list-interaction-inject-release: list=telemetry-registers logical=1 source=integration-test' "$LOG"
grep -q 'list-selection: list=telemetry-registers logical=1 physical=1' "$LOG"
grep -q 'list-navigation: logical=1 -> 2 viewport=0' "$LOG"
grep -q 'list-navigation: logical=2 -> 3 viewport=1' "$LOG"
grep -q 'virtual-list scroll-submit: list=telemetry-registers viewport=1' "$LOG"
grep -q 'worklist=no-packets' "$LOG"

echo "PASS: synthetic release reused production selection and keyboard navigation paths"
grep -E 'list-interaction-inject-release:|list-selection:|list-navigation:|virtual-list scroll-submit:' "$LOG" | tail -n 20
