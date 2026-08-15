#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROFILE_ID=noir-vulkan-gpu-matrix-v1
FINGERPRINT=fnv1a64:b9abfd758142e4cc
STRICT_SCENE="$ROOT/out/profile-admission-strict-fresh.scene.json"
PERMISSIVE_SCENE="$ROOT/out/profile-admission-permissive-stale.scene.json"

base_env=(
  "PLTCOLLECTS=$ROOT:"
  "NOIR_COST_PROFILE=$ROOT/profiles/registry.json"
  "NOIR_PROFILE_ID=$PROFILE_ID"
  "NOIR_FRESHNESS_MANIFEST=$ROOT/out/calibration-manifest.json"
  "NOIR_FRESHNESS_SCENE_FINGERPRINT=$FINGERPRINT"
)

cd "$ROOT"
env "${base_env[@]}" NOIR_PROFILE_ADMISSION=strict \
  NOIR_FRESHNESS_DIAGNOSTIC="$ROOT/out/freshness-fresh.json" \
  racket tools/export-dashboard.rkt "$STRICT_SCENE"

set +e
env "${base_env[@]}" NOIR_PROFILE_ADMISSION=strict \
  NOIR_FRESHNESS_DIAGNOSTIC="$ROOT/out/freshness-stale.json" \
  racket tools/export-dashboard.rkt "$ROOT/out/profile-admission-strict-stale.scene.json" \
  >/tmp/noir-profile-admission-strict-stale.stdout 2>/tmp/noir-profile-admission-strict-stale.stderr
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "strict admission unexpectedly accepted a stale artifact" >&2
  exit 1
fi
grep -q 'strict Profile Admission rejected' /tmp/noir-profile-admission-strict-stale.stderr

env "${base_env[@]}" NOIR_PROFILE_ADMISSION=permissive \
  NOIR_FRESHNESS_DIAGNOSTIC="$ROOT/out/freshness-stale.json" \
  racket tools/export-dashboard.rkt "$PERMISSIVE_SCENE"

node "$ROOT/tools/check-profile-admission.js" "$STRICT_SCENE" "$PERMISSIVE_SCENE"
echo 'Noir Racket strict/permissive Profile Admission verified.'
