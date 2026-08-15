#!/usr/bin/env bash
# rigorous_benchmark.sh - 统计学正确的 Noir vs GPUI 基准测试
set -euo pipefail

SESSIONS=5
WARMUP_BATCHES=50
MEASUREMENT_BATCHES=200
CLICKS_PER_BATCH=25
OUTPUT_DIR="data/rigorous-$(date +%Y%m%d-%H%M%S)"
DISPLAY_NUM=:93

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NOIR_BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
NOIR_SCENE="$ROOT/out/virtual-list-dashboard.scene.json"
GPUI_BIN="$ROOT/gpui-virtual-list-benchmark/target/release/gpui-virtual-list-benchmark"

mkdir -p "$OUTPUT_DIR"

# 记录全局环境
cat > "$OUTPUT_DIR/global-env.json" << EOF
{
  "protocol_version": "rigorous-v1",
  "sessions": $SESSIONS,
  "warmup_batches": $WARMUP_BATCHES,
  "measurement_batches": $MEASUREMENT_BATCHES,
  "clicks_per_batch": $CLICKS_PER_BATCH,
  "total_observations_per_framework": $((SESSIONS * MEASUREMENT_BATCHES)),
  "gpu": "AMD Radeon 780M",
  "driver": "Mesa Dozen 26.1.7",
  "os": "$(uname -s) $(uname -r)",
  "wgpu_backend": "vulkan",
  "display": "Xvfb (virtual)",
  "start_time": "$(date -Iseconds)"
}
EOF

# 启动 Xvfb
Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 >/tmp/rigorous-xvfb.log 2>&1 &
XVFB_PID=$!
trap 'kill "$XVFB_PID" 2>/dev/null || true; wait "$XVFB_PID" 2>/dev/null || true' EXIT
sleep 2

run_batch() {
    local framework="$1"
    local clicks="$2"
    local log="/tmp/${framework}-batch-$$.log"
    local app_pid window start end count expected x y elapsed
    
    if [[ "$framework" == "noir" ]]; then
        DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
            "$NOIR_BIN" "$NOIR_SCENE" >"$log" 2>&1 &
        expected='state-slot write: action=refresh-list'
        x=300; y=261
    else
        DISPLAY="$DISPLAY_NUM" XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
            "$GPUI_BIN" >"$log" 2>&1 &
        expected='gpui-refresh-event count='
        x=300; y=210
    fi
    
    app_pid=$!
    sleep 2
    
    window=$(DISPLAY="$DISPLAY_NUM" xdotool search --onlyvisible --name '.*' | tail -n 1)
    
    start=$(date +%s%N)
    DISPLAY="$DISPLAY_NUM" xdotool mousemove --window "$window" "$x" "$y" \
        click --repeat "$clicks" --delay 0 1 >/dev/null 2>&1
    
    # 等待所有事件完成
    for _ in $(seq 1 300); do
        count=$(grep -c "$expected" "$log" 2>/dev/null || echo 0)
        if [[ "$count" -ge "$clicks" ]]; then break; fi
        sleep 0.01
    done
    end=$(date +%s%N)
    
    count=$(grep -c "$expected" "$log" 2>/dev/null || echo 0)
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
    rm -f "$log"
    
    if [[ "$count" -ne "$clicks" ]]; then
        echo "WARNING: $framework batch incomplete: $count/$clicks events" >&2
        return 1
    fi
    
    elapsed=$((end - start))
    echo "$elapsed"
}

for session in $(seq 1 $SESSIONS); do
    SESSION_ID="session-$(printf "%02d" $session)"
    echo "=== Starting $SESSION_ID ($(date)) ===" | tee -a "$OUTPUT_DIR/progress.log"
    
    # 记录 session 环境
    cat > "$OUTPUT_DIR/${SESSION_ID}-env.json" << EOF
{
  "session_id": "$SESSION_ID",
  "session_number": $session,
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown')",
  "start_time": "$(date -Iseconds)"
}
EOF
    
    # 预热阶段
    echo "  Warming up ($WARMUP_BATCHES batches)..." | tee -a "$OUTPUT_DIR/progress.log"
    for i in $(seq 1 $WARMUP_BATCHES); do
        run_batch noir $CLICKS_PER_BATCH >/dev/null || echo "  Warmup noir $i failed" >&2
        run_batch gpui $CLICKS_PER_BATCH >/dev/null || echo "  Warmup gpui $i failed" >&2
    done
    
    # 生成随机顺序（区组化：每个区组包含 1 noir + 1 gpui）
    echo "  Generating randomized block order..." | tee -a "$OUTPUT_DIR/progress.log"
    ORDER=""
    for block in $(seq 1 $MEASUREMENT_BATCHES); do
        if (( RANDOM % 2 )); then
            ORDER="$ORDER noir gpui "
        else
            ORDER="$ORDER gpui noir "
        fi
    done
    
    # 正式采集
    echo "  Collecting measurements ($MEASUREMENT_BATCHES batches per framework)..." | tee -a "$OUTPUT_DIR/progress.log"
    batch_id=0
    noir_count=0
    gpui_count=0
    
    for framework in $ORDER; do
        elapsed=$(run_batch "$framework" $CLICKS_PER_BATCH) || {
            echo "  Batch failed: $framework batch_id=$batch_id" | tee -a "$OUTPUT_DIR/progress.log"
            continue
        }
        
        ns_per_handler=$(awk -v t="$elapsed" -v n="$CLICKS_PER_BATCH" 'BEGIN { printf "%.3f", t / n }')
        
        if [[ "$framework" == "noir" ]]; then
            block_id=$((noir_count))
            noir_count=$((noir_count + 1))
        else
            block_id=$((gpui_count))
            gpui_count=$((gpui_count + 1))
        fi
        
        cat >> "$OUTPUT_DIR/${SESSION_ID}-${framework}.jsonl" << EOF
{"session_id":"$SESSION_ID","framework":"$framework","batch_id":$batch_id,"block_id":$block_id,"clicks":$CLICKS_PER_BATCH,"total_ns":$elapsed,"ns_per_handler":$ns_per_handler,"metric":"x11_input_to_handler"}
EOF
        
        batch_id=$((batch_id + 1))
        
        # 进度报告
        if (( batch_id > 0 && batch_id % 50 == 0 )); then
            echo "    Progress: $batch_id/$((MEASUREMENT_BATCHES * 2)) batches (noir: $noir_count, gpui: $gpui_count)" | tee -a "$OUTPUT_DIR/progress.log"
        fi
    done
    
    echo "  Completed $SESSION_ID: noir=$noir_count batches, gpui=$gpui_count batches" | tee -a "$OUTPUT_DIR/progress.log"
    
    # Session 间冷却
    if (( session < SESSIONS )); then
        echo "  Cooling down for 60 seconds..." | tee -a "$OUTPUT_DIR/progress.log"
        sleep 60
    fi
done

echo "=== All sessions completed ($(date)) ===" | tee -a "$OUTPUT_DIR/progress.log"
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Next step: Run analysis with:"
echo "  python3 tools/analyze_rigorous_benchmark.py $OUTPUT_DIR"
