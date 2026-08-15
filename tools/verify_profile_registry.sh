#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$ROOT/profiles/registry.json"
MATCHED="$ROOT/out/registry-match.scene.json"
FALLBACK="$ROOT/out/registry-fallback.scene.json"
export PLTCOLLECTS="$ROOT:/usr/share/racket/collects"

NOIR_COST_PROFILE="$REGISTRY" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
  racket "$ROOT/tools/export-dashboard.rkt" "$MATCHED"
grep -q '"profile_id":"noir-vulkan-gpu-matrix-v1"' "$MATCHED"

NOIR_COST_PROFILE="$REGISTRY" \
NOIR_PROFILE_ID="missing-device-profile" \
  racket "$ROOT/tools/export-dashboard.rkt" "$FALLBACK"
grep -q '"profile_id":"noir-static-cost-v1"' "$FALLBACK"

cd "$ROOT/wgpu-verify"
XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime WGPU_BACKEND=vulkan \
  cargo run --release --bin noir-wgpu-verify -- "$MATCHED" out/noir-registry > out/registry-verification.log
grep -q 'profile=noir-vulkan-gpu-matrix-v1' out/registry-verification.log

echo "Profile registry selection and fallback verified."
