#!/usr/bin/env bash
# Run compiler-selected component matrices only on a non-CPU Vulkan adapter.
# The output is an input to tools/analyze_real_gpu_component_matrix_v1.py.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="${OUT_ROOT:-$ROOT/data/material-component-gpu-$(date +%Y%m%d-%H%M%S)}"
SESSIONS="${SESSIONS:-5}"
WARMUP="${WARMUP:-25}"
SAMPLES="${SAMPLES:-100}"
USE_XVFB="${USE_XVFB:-0}"
DISPLAY_NUM="${DISPLAY_NUM:-:463}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# Use standard Rust toolchain if noir-specific one doesn't exist
if [[ -d "/home/ubuntu/.rustup-noir-wgpu30" ]]; then
  TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
  export PATH="$TOOLCHAIN:$PATH"
  export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
  export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30
fi
export WGPU_BACKEND=vulkan

BIN="$ROOT/wgpu-verify/target/release/noir_winit_host"
DASH_SCENE="$ROOT/out/material-profile-dashboard.scene.json"
OVERLAY_SCENE="$ROOT/out/material-overlay-showcase.scene.json"
mkdir -p "$OUT_ROOT"

if ! command -v vulkaninfo >/dev/null 2>&1; then
  echo 'ERROR: vulkaninfo is required to gate real-GPU measurements.' >&2
  exit 2
fi
VULKAN_SUMMARY="$OUT_ROOT/vulkaninfo-summary.txt"
vulkaninfo --summary >"$VULKAN_SUMMARY" 2>&1 || true

# Check if at least one non-CPU GPU exists
if ! grep -Eq 'GPU[0-9]+:' "$VULKAN_SUMMARY"; then
  echo "ERROR: no Vulkan physical GPU was detected." >&2
  exit 43
fi
has_real_gpu=0
in_gpu_block=0
is_cpu_device=0
while IFS= read -r line; do
  if [[ "$line" =~ ^GPU[0-9]+: ]]; then
    in_gpu_block=1
    is_cpu_device=0
  elif [[ "$in_gpu_block" == 1 && "$line" =~ deviceType.*PHYSICAL_DEVICE_TYPE_(INTEGRATED_GPU|DISCRETE_GPU) ]]; then
    has_real_gpu=1
    break
  elif [[ "$in_gpu_block" == 1 && "$line" =~ deviceType.*CPU ]]; then
    is_cpu_device=1
    in_gpu_block=0
  elif [[ "$in_gpu_block" == 1 && "$line" =~ ^GPU[0-9]+: ]]; then
    in_gpu_block=0
  fi
done < "$VULKAN_SUMMARY"
if [[ "$has_real_gpu" -eq 0 ]]; then
  echo "ERROR: Only CPU Vulkan adapters detected; refusing to publish pseudo-real-GPU measurements." >&2
  echo "See $VULKAN_SUMMARY" >&2
  exit 42
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'REAL_GPU_COMPONENT_MATRIX_V1: READY adapter_gate=PASS sessions=%s warmup=%s samples=%s output=%s\n' \
    "$SESSIONS" "$WARMUP" "$SAMPLES" "$OUT_ROOT"
  exit 0
fi

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-component-matrix-racket.log 2>&1
NOIR_ENTRY_MODULE=examples/material-profile-dashboard.rkt PLTCOLLECTS="$ROOT:" racket tools/export-dashboard.rkt "$DASH_SCENE"
NOIR_ENTRY_MODULE=examples/material-overlay-showcase.rkt PLTCOLLECTS="$ROOT:" racket tools/export-dashboard.rkt "$OVERLAY_SCENE"
cargo build --release --manifest-path "$ROOT/wgpu-verify/Cargo.toml" --bin noir_winit_host >/tmp/noir-component-matrix-cargo.log 2>&1

xvfb_pid=""
cleanup() { [[ -n "$xvfb_pid" ]] && kill "$xvfb_pid" 2>/dev/null || true; }
trap cleanup EXIT
if [[ "$USE_XVFB" == "1" ]]; then
  rm -f "/tmp/.X${DISPLAY_NUM#:}-lock"
  Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-component-matrix-xvfb.log 2>&1 &
  xvfb_pid=$!
  export DISPLAY="$DISPLAY_NUM"
  sleep 1
fi
: "${DISPLAY:?set DISPLAY to the real GPU X11/WSLg display, or use USE_XVFB=1 on a verified hardware-backed Xvfb setup}"

python3 - "$OUT_ROOT/run-manifest.json" "$SESSIONS" "$WARMUP" "$SAMPLES" <<'PY'
import json, os, subprocess, sys
out, sessions, warmup, samples = sys.argv[1:]
root = os.getcwd()
manifest = {
  "schema": "noir-real-gpu-component-matrix-v1",
  "git_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
  "host": os.uname().nodename,
  "display": os.environ.get("DISPLAY"),
  "backend": os.environ.get("WGPU_BACKEND"),
  "sessions": int(sessions), "warmup": int(warmup), "samples": int(samples),
  "scenes": ["material-profile-dashboard", "material-overlay-showcase"],
}
open(out, "w", encoding="utf-8").write(json.dumps(manifest, indent=2) + "\n")
PY

for session in $(seq 1 "$SESSIONS"); do
  session_id=$(printf 'session-%02d' "$session")
  # A block contains both component fixtures; shuffle each session and record the order.
  if (( RANDOM % 2 )); then order=(dashboard overlay); else order=(overlay dashboard); fi
  printf '%s\n' "${order[*]}" >"$OUT_ROOT/$session_id-order.txt"
  for fixture in "${order[@]}"; do
    case "$fixture" in
      dashboard) scene="$DASH_SCENE" ;;
      overlay) scene="$OVERLAY_SCENE" ;;
    esac
    report="$OUT_ROOT/$session_id-$fixture-replay-matrix.json"
    DISPLAY="$DISPLAY" "$BIN" "$scene" --replay-matrix "$report" --warmup "$WARMUP" --samples "$SAMPLES" \
      >"$OUT_ROOT/$session_id-$fixture-host.log" 2>&1
    python3 - "$report" <<'PY'
import json, sys
report = json.load(open(sys.argv[1], encoding='utf-8'))
name = str(report.get('adapter_name', '')).lower()
assert report.get('schema') == 'noir-wgpu-replay-matrix-v2'
assert report.get('timestamp_query_supported') is True
assert not any(token in name for token in ('llvmpipe', 'lavapipe', 'cpu'))
assert all(row.get('mode') != 'compiler-selected' or row.get('compiler_selected', {}).get('self_consistent') is True for row in report['rows'])
PY
  done
done
python3 "$ROOT/tools/analyze_real_gpu_component_matrix_v1.py" "$OUT_ROOT"
printf 'REAL_GPU_COMPONENT_MATRIX_V1: PASS output=%s\n' "$OUT_ROOT"
