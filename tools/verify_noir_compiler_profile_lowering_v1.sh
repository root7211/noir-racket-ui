#!/usr/bin/env bash
# Differential regression for the first pure Rust Noir compiler lowering pass.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/noir-compiler-profile-lowering"
IR_MANIFEST="$ROOT/noir-ir/Cargo.toml"
COMPILER_MANIFEST="$ROOT/noir-compiler/Cargo.toml"
IR_BIN="$ROOT/noir-ir/target/release/noir-ir"
COMPILER_BIN="$ROOT/noir-compiler/target/release/noir-compiler"
export PATH="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

mkdir -p "$OUT"
cd "$ROOT"
cargo test --release --manifest-path "$IR_MANIFEST" >/tmp/noir-compiler-ir-test.log 2>&1
cargo test --release --manifest-path "$COMPILER_MANIFEST" >/tmp/noir-compiler-test.log 2>&1

run_profile() {
  local profile="$1"
  local module="$2"
  local app="$3"
  local scene="$OUT/${profile}.scene.json"
  local racket_plan="$OUT/${profile}.racket.json"
  local rust_plan="$OUT/${profile}.rust.json"

  NOIR_ENTRY_MODULE="$module" PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt "$scene" >"$OUT/${profile}.export.log" 2>&1
  PLTCOLLECTS="$ROOT:" racket tools/export_noir_compiler_profile_plan.rkt "$scene" "$racket_plan" >"$OUT/${profile}.racket.log" 2>&1
  "$COMPILER_BIN" lower "$app" "$profile" "$rust_plan" >"$OUT/${profile}.rust.log" 2>&1
  "$IR_BIN" diff-profile "$racket_plan" "$rust_plan" >"$OUT/${profile}.diff.log" 2>&1
  grep -Fq 'NOIR_IR_PROFILE_DIFFERENTIAL: PASS' "$OUT/${profile}.diff.log"
  printf 'noir-compiler profile=%s app=%s: PASS\n' "$profile" "$app"
}

run_profile standard examples/application-layer-workbench.rkt operations
run_profile compact examples/application-layer-workbench-compact.rkt operations-compact

# The first pass has a deliberately closed input surface.
if "$COMPILER_BIN" lower operations experimental "$OUT/invalid-profile.json" >"$OUT/invalid-profile.log" 2>&1; then
  echo 'noir-compiler accepted an unknown profile' >&2
  exit 1
fi
grep -Fq 'unsupported profile experimental' "$OUT/invalid-profile.log"
if "$COMPILER_BIN" lower Operations standard "$OUT/invalid-id.json" >"$OUT/invalid-id.log" 2>&1; then
  echo 'noir-compiler accepted an invalid application ID' >&2
  exit 1
fi
grep -Fq 'invalid application identifier Operations' "$OUT/invalid-id.log"

# The shared oracle must reject semantic plan drift, not just parse both files.
tampered="$OUT/standard.tampered.json"
cp "$OUT/standard.rust.json" "$tampered"
sed -i '0,/"word_count": 32/s//"word_count": 31/' "$tampered"
if "$IR_BIN" diff-profile "$OUT/standard.rust.json" "$tampered" >"$OUT/tampered.log" 2>&1; then
  echo 'noir-ir accepted tampered compiler word geometry' >&2
  exit 1
fi
grep -Fq 'profile acknowledged-row-state mismatch' "$OUT/tampered.log"
printf '%s\n' 'NOIR_COMPILER_PROFILE_LOWERING_V1_REGRESSION: PASS'
