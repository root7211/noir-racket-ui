#!/usr/bin/env bash
# monitor_benchmark.sh - 监控基准测试进度

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <data_dir>"
    echo "Example: $0 data/rigorous-20260815-192000"
    exit 1
fi

DATA_DIR="$1"

if [ ! -d "$DATA_DIR" ]; then
    echo "Error: Directory not found: $DATA_DIR"
    exit 1
fi

echo "Monitoring benchmark in: $DATA_DIR"
echo "Press Ctrl+C to stop monitoring"
echo ""

while true; do
    clear
    echo "=== Benchmark Progress Monitor ==="
    echo "Time: $(date)"
    echo ""
    
    if [ -f "$DATA_DIR/progress.log" ]; then
        echo "--- Latest Progress ---"
        tail -10 "$DATA_DIR/progress.log"
        echo ""
    fi
    
    echo "--- Data Files ---"
    find "$DATA_DIR" -name "*.jsonl" -exec wc -l {} \; | awk '{print $2": "$1" lines"}' | sort
    echo ""
    
    echo "--- Sessions ---"
    ls -1 "$DATA_DIR"/session-*-env.json 2>/dev/null | wc -l | xargs echo "Completed sessions:"
    
    sleep 5
done
