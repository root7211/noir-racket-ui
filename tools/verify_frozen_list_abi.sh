#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/out/data-register-table-10000.scene.json"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_ID="${NOIR_ABI_FREEZE_DISPLAY:-:100}"
SUCCESS_LOG="${NOIR_ABI_FREEZE_LOG:-/tmp/noir-abi-freeze-success.log}"

if [[ ! -x "$HOST" ]]; then
  echo "missing release host: $HOST" >&2
  exit 1
fi

# Re-export through the normal attested compiler path; this must be done before
# each ABI oracle so a stale Scene cannot accidentally satisfy a newer host.
(
  cd "$ROOT"
  NOIR_ENTRY_MODULE=examples/data-register-table-10000.rkt PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt out/data-register-table-10000.scene.json
) >/tmp/noir-abi-freeze-export.log 2>&1

grep -Fq '"abi_contracts"' "$SCENE"
grep -Fq '"schema":"noir-virtual-list-plan-v1"' "$SCENE"
grep -Fq '"schema":"noir-row-activation-plan-v1"' "$SCENE"
grep -Fq '"abi_schema":"noir-virtual-list-plan-v1"' "$SCENE"
grep -Fq '"abi_schema":"noir-row-activation-plan-v1"' "$SCENE"

Xvfb "$DISPLAY_ID" -screen 0 1280x720x24 >/tmp/noir-abi-freeze-xvfb.log 2>&1 &
XVFB_PID=$!
HOST_PID=""
cleanup() {
  kill "$HOST_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1

# Positive path: both global contracts and concrete artifact revisions admit.
DISPLAY="$DISPLAY_ID" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  "$HOST" "$SCENE" >"$SUCCESS_LOG" 2>&1 &
HOST_PID=$!
sleep 4
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""
grep -Fq 'compiler ABI contracts: virtual-list=noir-virtual-list-plan-v1@1 row-activation=noir-row-activation-plan-v1@1 scrollbar=noir-scrollbar-plan-v1@1 list-navigation=noir-list-navigation-plan-v1@1 frozen' "$SUCCESS_LOG"
grep -Fq 'compiler virtual lists: telemetry-registers capacity=4 viewport=3x28 row-tiles=[0, 1, 2]' "$SUCCESS_LOG"
grep -Fq 'compiler row activation: list=telemetry-registers action=refresh-tick slot=0 batch=coalesced-activate-refresh-registers tile-mask=0x0000000000000001 worklist=2' "$SUCCESS_LOG"

TOP_TAMPER=/tmp/noir-abi-top-contract-v9.scene.json
ROW_TAMPER=/tmp/noir-abi-row-artifact-v9.scene.json
MISSING_TAMPER=/tmp/noir-abi-virtual-list-missing-glyph-slots.scene.json
sed 's/"revision":1,"schema":"noir-virtual-list-plan-v1"/"revision":9,"schema":"noir-virtual-list-plan-v1"/' "$SCENE" > "$TOP_TAMPER"
sed 's/"abi_schema":"noir-row-activation-plan-v1"/"abi_schema":"noir-row-activation-plan-v9"/' "$SCENE" > "$ROW_TAMPER"
sed 's/"row_glyph_slots":/"removed_row_glyph_slots":/' "$SCENE" > "$MISSING_TAMPER"

expect_reject() {
  local scene="$1"
  local expected="$2"
  local log="$3"
  set +e
  DISPLAY="$DISPLAY_ID" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan "$HOST" "$scene" >"$log" 2>&1
  local status=$?
  set -e
  [[ "$status" -ne 0 ]]
  grep -Fq "$expected" "$log"
}

expect_reject "$TOP_TAMPER" 'unsupported virtual_list_plan ABI noir-virtual-list-plan-v1@9; expected noir-virtual-list-plan-v1@1' /tmp/noir-abi-freeze-top-tamper.log
expect_reject "$ROW_TAMPER" 'row activation telemetry-registers has unsupported ABI noir-row-activation-plan-v9@1' /tmp/noir-abi-freeze-row-tamper.log
expect_reject "$MISSING_TAMPER" 'missing field `row_glyph_slots`' /tmp/noir-abi-freeze-missing-field.log

echo 'PASS: frozen ABI v1 accepted exact contracts and rejected global revision drift, artifact schema drift, and required-field omission'
grep -E 'compiler ABI contracts:|compiler virtual lists:|compiler row activation:' "$SUCCESS_LOG"
