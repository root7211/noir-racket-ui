#!/usr/bin/env bash
# 快速验证测试：2 sessions × 20 batches
set -euo pipefail

SESSIONS=2
WARMUP_BATCHES=10
MEASUREMENT_BATCHES=20
CLICKS_PER_BATCH=25

export SESSIONS WARMUP_BATCHES MEASUREMENT_BATCHES CLICKS_PER_BATCH

bash tools/rigorous_benchmark.sh
