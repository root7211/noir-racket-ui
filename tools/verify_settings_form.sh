#!/usr/bin/env bash
# 真实 X11/wgpu 表单验证：settings-form/form-row 已在导出前内联为基础 primitives。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCENE="$ROOT/out/settings-dashboard.scene.json"
LOG="$ROOT/wgpu-verify/out/settings-dashboard-e2e.log"
HOST="$ROOT/wgpu-verify/target/release/noir_winit_host"
DISPLAY_NUM=:116

cd "$ROOT"
PLTCOLLECTS="$ROOT:" NOIR_ENTRY_MODULE="examples/settings-dashboard.rkt" \
  racket tools/export-dashboard.rkt "$SCENE"

# Scene preflight: no component runtime tags; apply-all is one compiler-fixed transaction.
! grep -q '"tag":"form-row"' "$SCENE"
! grep -q '"tag":"settings-form"' "$SCENE"
grep -q '"transactions"' "$SCENE"
grep -q '"id":"apply-all"' "$SCENE"
grep -q '"field_slots":\[0,1,2\]' "$SCENE"
grep -q '"state_indices":\[2,0,1\]' "$SCENE"
grep -q '"tile_ids":\[0,1,2\]' "$SCENE"
[[ $(grep -o '"kind":"commit-group"' "$SCENE" | wc -l) -eq 3 ]]
[[ $(grep -o '"transaction_index":0' "$SCENE" | wc -l) -eq 5 ]]
grep -q '"focus_slot":2,"key":"escape","kind":"reset"' "$SCENE"
[[ -x "$HOST" ]]

rm -f "$LOG"
Xvfb "$DISPLAY_NUM" -screen 0 640x360x24 >/tmp/noir-settings-form-xvfb.log 2>&1 &
XVFB_PID=$!
HOST_PID=""
cleanup() {
  [[ -n "$HOST_PID" ]] && kill "$HOST_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1

DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp stdbuf -oL "$HOST" "$SCENE" >"$LOG" 2>&1 &
HOST_PID=$!
sleep 2
WINDOW_ID=$(DISPLAY="$DISPLAY_NUM" xdotool search --name 'Noir Glyph Atlas host' | head -n1)
DISPLAY="$DISPLAY_NUM" xdotool windowfocus "$WINDOW_ID"

# slot 0: Escape initial pending=5, then 7/2/0. slot 1: Tab then 9/overflowed 9.
# slot 2: Tab, digit 4 -> Backspace -> digit 4. Return atomically commits all three pending registers;
# the following Escape proves group commit does not widen field-local discard. These are genuine X11 events.
DISPLAY="$DISPLAY_NUM" xdotool key Escape
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool key 7
sleep .12
DISPLAY="$DISPLAY_NUM" xdotool key 2
sleep .12
DISPLAY="$DISPLAY_NUM" xdotool key 0
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool key Tab
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool key 9
sleep .15
# initial pending=72: 72*10+9=729; a second 9 would be 7299 and must reject before any GPU write.
DISPLAY="$DISPLAY_NUM" xdotool key 9
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool key Tab
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool key 4
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool key BackSpace
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool key 4
sleep .15
DISPLAY="$DISPLAY_NUM" xdotool key Return
sleep .25
DISPLAY="$DISPLAY_NUM" xdotool key Escape
sleep .4

kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

# Startup proof and runtime evidence: no runtime component traversal, field lookup or tile geometry calculation.
grep -q 'compiler digit register: slot=0 field=sample-interval-row$field radix=10 digits=3 initial=5 reset=0 maximum=999' "$LOG"
grep -q 'compiler digit register: slot=1 field=alert-threshold-row$field radix=10 digits=3 initial=72 reset=0 maximum=999' "$LOG"
grep -q 'compiler digit register: slot=2 field=batch-size-row$field radix=10 digits=3 initial=16 reset=0 maximum=999' "$LOG"
grep -q 'compiler transaction: index=0 id=apply-all fields=\[0, 1, 2\] states=\[2, 0, 1\] mask=0x0000000000000007' "$LOG"
grep -q 'compiler keyboard command: slot=0 Enter -> commit-group apply-all index=0 mask=0x0000000000000007' "$LOG"
grep -q 'compiler keyboard command: slot=1 Enter -> commit-group apply-all index=0 mask=0x0000000000000007' "$LOG"
grep -q 'compiler keyboard command: slot=2 Enter -> commit-group apply-all index=0 mask=0x0000000000000007' "$LOG"
grep -Fq 'keyboard-command Escape: slot=0 field=sample-interval-row$field charset=digits reset_glyph_offsets=[1216, 1248, 1280] mask=0x0000000000000001 pending=5->0' "$LOG"
grep -q 'keyboard-transition insert: slot=0 field=sample-interval-row$field key=digit-7 cursor=0->1 glyph-id-patch \[1216..1220) glyph_id=7 pending=0->7 register-op=append-digit radix=10 operand=7' "$LOG"
grep -q 'keyboard-transition insert: slot=0 field=sample-interval-row$field key=digit-0 cursor=2->3 glyph-id-patch \[1280..1284) glyph_id=0 pending=72->720 register-op=append-digit radix=10 operand=0' "$LOG"
grep -Fq 'keyboard-command Enter: slot=2 field=batch-size-row$field kind=commit-group id=apply-all transaction_index=0 atomic=true commits=[field_slot=0:state_index=2:5->720, field_slot=1:state_index=0:72->729, field_slot=2:state_index=1:16->164] mask=0x0000000000000007' "$LOG"
grep -q 'focus-tab forward: slot 0 -> 1 / alert-threshold-row$field mask=0x0000000000000002' "$LOG"
grep -q 'keyboard-transition insert: slot=1 field=alert-threshold-row$field key=digit-9 cursor=0->1 glyph-id-patch \[1888..1892) glyph_id=9 pending=72->729 register-op=append-digit radix=10 operand=9' "$LOG"
grep -q 'keyboard-transition register-overflow: slot=1 field=alert-threshold-row$field key=digit-9 pending=729 radix=10 operand=9 maximum=999 policy=reject' "$LOG"
grep -q 'render-request-enqueue keyboard-command: mask=0x0000000000000007 strategy=None worklist=6' "$LOG"
grep -q 'focus-tab forward: slot 1 -> 2 / batch-size-row$field mask=0x0000000000000004' "$LOG"
grep -q 'keyboard-transition insert: slot=2 field=batch-size-row$field key=digit-4 cursor=0->1 glyph-id-patch \[2336..2340) glyph_id=4 pending=16->164 register-op=append-digit radix=10 operand=4' "$LOG"
grep -q 'keyboard-transition backspace: slot=2 field=batch-size-row$field cursor=1->0 glyph-id-patch \[2336..2340) glyph_id=0 pending=164->16 register-op=drop-last radix=10' "$LOG"
grep -Fq 'keyboard-command Escape: slot=2 field=batch-size-row$field charset=digits reset_glyph_offsets=[2336, 2368, 2400] mask=0x0000000000000004 pending=164->0' "$LOG"
grep -q 'render-request-enqueue keyboard-command: mask=0x0000000000000004 strategy=None worklist=5' "$LOG"
# State-to-Packet local lists: field slots 0/1/2 map to [3]/[6]/[9]; apply-all maps to [3,6,9].
grep -q 'compiler packet worklists: all-packets#0=\[0, 1, 2, 3, 4, 5, 6, 7, 8, 9\]; dynamic-packets#1=\[3, 6, 9\]; no-packets#2=\[\]; field-sample-interval-row$field#3=\[3\]; field-alert-threshold-row$field#4=\[6\]; field-batch-size-row$field#5=\[9\]; transaction-apply-all#6=\[3, 6, 9\]' "$LOG"
grep -q 'render-request-enqueue keyboard-transition: mask=0x0000000000000001 strategy=None worklist=3' "$LOG"
grep -q 'packet-activity-dispatch worklist=field-sample-interval-row$field index=3 packets=\[3\] workgroups=1 workgroup_size=32 output=activity+indirect' "$LOG"
grep -q 'packet-activity-dispatch worklist=field-alert-threshold-row$field index=4 packets=\[6\] workgroups=1 workgroup_size=32 output=activity+indirect' "$LOG"
grep -q 'packet-activity-dispatch worklist=field-batch-size-row$field index=5 packets=\[9\] workgroups=1 workgroup_size=32 output=activity+indirect' "$LOG"
grep -q 'render-request-enqueue keyboard-command: mask=0x0000000000000007 strategy=None worklist=6' "$LOG"
grep -q 'packet-activity-dispatch worklist=transaction-apply-all index=6 packets=\[3, 6, 9\] workgroups=3 workgroup_size=32 output=activity+indirect' "$LOG"
grep -q 'packet-activity-skip worklist=no-packets index=2 packets=\[\] reason=compiler-empty' "$LOG"

printf 'Noir compiler form-row/settings-form X11 verification passed.\n'
