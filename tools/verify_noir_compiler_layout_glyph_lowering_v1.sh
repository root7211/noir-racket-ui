#!/usr/bin/env bash
# Differential regression for the second pure Rust Noir compiler lowering pass.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/noir-compiler-layout-glyph-lowering"
IR_MANIFEST="$ROOT/noir-ir/Cargo.toml"
COMPILER_MANIFEST="$ROOT/noir-compiler/Cargo.toml"
IR_BIN="$ROOT/noir-ir/target/release/noir-ir"
COMPILER_BIN="$ROOT/noir-compiler/target/release/noir-compiler"
export PATH="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT"
cargo test --release --manifest-path "$IR_MANIFEST" >/tmp/noir-layout-glyph-ir-test.log 2>&1
cargo test --release --manifest-path "$COMPILER_MANIFEST" >/tmp/noir-layout-glyph-compiler-test.log 2>&1
cargo build --release --manifest-path "$IR_MANIFEST" --bin noir-ir >/tmp/noir-layout-glyph-ir-build.log 2>&1
cargo build --release --manifest-path "$COMPILER_MANIFEST" --bin noir-compiler >/tmp/noir-layout-glyph-compiler-build.log 2>&1

run_profile() {
  local profile="$1"
  local module="$2"
  local app="$3"
  local scene="$OUT/${profile}.scene.json"
  local racket_projection="$OUT/${profile}.racket.json"
  local rust_projection="$OUT/${profile}.rust.json"

  NOIR_ENTRY_MODULE="$module" PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt "$scene" >"$OUT/${profile}.export.log" 2>&1
  PLTCOLLECTS="$ROOT:" \
    racket tools/export_noir_compiler_layout_glyph_plan.rkt "$scene" "$racket_projection" >"$OUT/${profile}.racket.log" 2>&1
  "$COMPILER_BIN" lower-layout-glyph "$app" "$profile" "$rust_projection" >"$OUT/${profile}.rust.log" 2>&1
  "$IR_BIN" diff-layout-glyph "$racket_projection" "$rust_projection" >"$OUT/${profile}.diff.log" 2>&1
  grep -Fq 'NOIR_IR_LAYOUT_GLYPH_DIFFERENTIAL: PASS' "$OUT/${profile}.diff.log"
  printf 'noir-compiler layout-glyph profile=%s app=%s: PASS\n' "$profile" "$app"
}

run_profile standard examples/application-layer-workbench.rkt operations
run_profile compact examples/application-layer-workbench-compact.rkt operations-compact

# The second pass deliberately retains the first pass's closed application input surface.
if "$COMPILER_BIN" lower-layout-glyph operations experimental "$OUT/invalid-profile.json" >"$OUT/invalid-profile.log" 2>&1; then
  echo 'noir-compiler accepted an unknown layout-glyph profile' >&2
  exit 1
fi
grep -Fq 'unsupported profile experimental' "$OUT/invalid-profile.log"
if "$COMPILER_BIN" lower-layout-glyph Operations standard "$OUT/invalid-id.json" >"$OUT/invalid-id.log" 2>&1; then
  echo 'noir-compiler accepted an invalid layout-glyph application ID' >&2
  exit 1
fi
grep -Fq 'invalid application identifier Operations' "$OUT/invalid-id.log"

# Validation is semantic: it rejects well-formed JSON whose profile-derived geometry drifts.
geometry_tampered="$OUT/standard.geometry-tampered.json"
cp "$OUT/standard.rust.json" "$geometry_tampered"
sed -i '0,/"height": 128/s//"height": 127/' "$geometry_tampered"
if "$IR_BIN" verify-layout-glyph "$geometry_tampered" >"$OUT/geometry-tampered.log" 2>&1; then
  echo 'noir-ir accepted tampered Systems viewport geometry' >&2
  exit 1
fi
grep -Fq 'profile data viewport geometry mismatch' "$OUT/geometry-tampered.log"

# The dynamic counter's exposed range is part of the finite write-set contract.
glyph_tampered="$OUT/standard.glyph-tampered.json"
cp "$OUT/standard.rust.json" "$glyph_tampered"
sed -i '0,/"glyph_count": 8/s//"glyph_count": 7/' "$glyph_tampered"
if "$IR_BIN" verify-layout-glyph "$glyph_tampered" >"$OUT/glyph-tampered.log" 2>&1; then
  echo 'noir-ir accepted tampered acknowledged-count glyph geometry' >&2
  exit 1
fi
grep -Fq 'profile acknowledged count glyph endpoint mismatch' "$OUT/glyph-tampered.log"
printf '%s\n' 'NOIR_COMPILER_LAYOUT_GLYPH_LOWERING_V1_REGRESSION: PASS'
