#!/usr/bin/env bash
# verify_analysis_reproducibility.sh - 验证分析在干净环境中可重现
set -euo pipefail

echo "=== Verifying Analysis Reproducibility ==="
echo

DATA_DIR="${1:-data/rigorous-20260815-192350}"

if [ ! -d "$DATA_DIR" ]; then
    echo "ERROR: Data directory not found: $DATA_DIR"
    exit 1
fi

echo "[1/4] Check Python dependencies..."
python3 -c "import numpy, scipy.stats; print(f'numpy: {numpy.__version__}, scipy: {scipy.__version__}')" || {
    echo "ERROR: Missing dependencies. Install with:"
    echo "  python3 -m pip install --break-system-packages 'numpy>=1.21.6,<1.28.0' scipy"
    exit 1
}
echo "✓ Dependencies available"

echo "[2/4] Verify NumPy version compatibility..."
NUMPY_VER=$(python3 -c "import numpy; print(numpy.__version__)")
python3 -c "
import numpy as np
major, minor = map(int, '$NUMPY_VER'.split('.')[:2])
assert 1 <= major <= 1 and 21 <= minor < 28, f'NumPy {major}.{minor} incompatible with scipy 1.11.4'
print('✓ NumPy $NUMPY_VER compatible')
"

echo "[3/4] Run analysis..."
python3 tools/analyze_rigorous_benchmark.py "$DATA_DIR" > /tmp/analysis-verify.log 2>&1 || {
    echo "ERROR: Analysis failed"
    tail -20 /tmp/analysis-verify.log
    exit 1
}
echo "✓ Analysis completed"

echo "[4/4] Verify results..."
[ -f "$DATA_DIR/analysis-results.json" ] || {
    echo "ERROR: analysis-results.json not generated"
    exit 1
}

CONCLUSION=$(python3 -c "import json; print(json.load(open('$DATA_DIR/analysis-results.json'))['conclusion'])")
echo "✓ Conclusion: $CONCLUSION"

echo
echo "=== Reproducibility verified ==="
cat /tmp/analysis-verify.log | grep -A 20 "Conclusion"
