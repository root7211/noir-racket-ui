#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROFILE_ID=noir-vulkan-gpu-matrix-v1
MANIFEST="$ROOT/out/attested-calibration-manifest.json"
FRESHNESS="$ROOT/out/attested-freshness.json"
STRICT_A="$ROOT/out/attested-strict-a.scene.json"
STRICT_B="$ROOT/out/attested-strict-b.scene.json"
MUTATED_REGISTRY="$ROOT/out/attestation-mutated-registry.json"

strict_env=(
  "PLTCOLLECTS=$ROOT:"
  "NOIR_COST_PROFILE=$ROOT/profiles/registry.json"
  "NOIR_PROFILE_ID=$PROFILE_ID"
  "NOIR_PROFILE_ADMISSION=strict"
  "NOIR_FRESHNESS_MANIFEST=$MANIFEST"
  "NOIR_FRESHNESS_DIAGNOSTIC=$FRESHNESS"
)

cd "$ROOT"
env "${strict_env[@]}" racket tools/export-dashboard.rkt "$STRICT_A"
env "${strict_env[@]}" racket tools/export-dashboard.rkt "$STRICT_B"

fingerprint_a=$(grep -o '"source_fingerprint_fnv1a64":"[^"]*"' "$STRICT_A" | head -1)
fingerprint_b=$(grep -o '"source_fingerprint_fnv1a64":"[^"]*"' "$STRICT_B" | head -1)
if [[ "$fingerprint_a" != "$fingerprint_b" ]]; then
  echo "canonical fingerprint changed across identical strict builds" >&2
  exit 1
fi
grep -q '"mode":"profile-guided"' "$STRICT_A"

# Whitespace is deliberately part of raw profile source identity in v1. The JSON remains valid,
# but the canonical profile artifact has changed and strict admission must reject old evidence.
cp profiles/registry.json "$MUTATED_REGISTRY"
printf '\n' >> "$MUTATED_REGISTRY"
set +e
env "PLTCOLLECTS=$ROOT:" "NOIR_COST_PROFILE=$MUTATED_REGISTRY" "NOIR_PROFILE_ID=$PROFILE_ID" \
  "NOIR_PROFILE_ADMISSION=strict" "NOIR_FRESHNESS_MANIFEST=$MANIFEST" \
  "NOIR_FRESHNESS_DIAGNOSTIC=$FRESHNESS" \
  racket tools/export-dashboard.rkt "$ROOT/out/attested-strict-mutated.scene.json" \
  >/tmp/noir-attestation-mutated.stdout 2>/tmp/noir-attestation-mutated.stderr
status=$?
set -e
rm -f "$MUTATED_REGISTRY"
if [[ "$status" -eq 0 ]]; then
  echo "strict admission unexpectedly accepted changed canonical profile input" >&2
  exit 1
fi
grep -q 'strict Profile Admission rejected' /tmp/noir-attestation-mutated.stderr
printf 'Noir Canonical Build Input and automatic Source Fingerprint verified: %s\n' "$fingerprint_a"
