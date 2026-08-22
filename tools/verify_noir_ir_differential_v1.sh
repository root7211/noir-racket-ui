#!/usr/bin/env bash
# Verify that the Racket compiler's application-layer Scene and the pure Rust noir-ir
# projection agree on the bounded workbench semantic subset. No renderer is started.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/noir-ir-differential"
CRATE="$ROOT/noir-ir"
BIN="$CRATE/target/release/noir-ir"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

mkdir -p "$OUT"
cd "$ROOT"
cargo build --release --manifest-path "$CRATE/Cargo.toml" --bin noir-ir >/tmp/noir-ir-differential-cargo.log 2>&1

run_profile() {
  local profile="$1"
  local module="$2"
  local app="$3"
  local scene="$OUT/${profile}.scene.json"
  local racket_projection="$OUT/${profile}.racket.json"
  local rust_projection="$OUT/${profile}.rust.json"
  local golden="$CRATE/golden/${profile}.json"

  NOIR_ENTRY_MODULE="$module" PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt "$scene" >"$OUT/${profile}.export.log" 2>&1
  PLTCOLLECTS="$ROOT:" racket tools/export_noir_ir_projection.rkt "$scene" "$racket_projection" >"$OUT/${profile}.racket.log" 2>&1
  "$BIN" project "$scene" "$rust_projection" >"$OUT/${profile}.rust.log" 2>&1
  "$BIN" diff "$racket_projection" "$rust_projection" >"$OUT/${profile}.diff.log" 2>&1
  "$BIN" diff "$racket_projection" "$golden" >"$OUT/${profile}.golden.log" 2>&1
  grep -Fq 'NOIR_IR_DIFFERENTIAL: PASS' "$OUT/${profile}.diff.log"
  grep -Fq 'NOIR_IR_DIFFERENTIAL: PASS' "$OUT/${profile}.golden.log"
  printf 'noir-ir differential profile=%s app=%s: PASS\n' "$profile" "$app"
}

run_profile standard examples/application-layer-workbench.rkt operations
run_profile compact examples/application-layer-workbench-compact.rkt operations-compact

# A semantic negative control: the canonical state word geometry is part of the migration contract.
tampered="$OUT/standard.tampered.json"
cp "$CRATE/golden/standard.json" "$tampered"
sed -i '0,/"word_count":32/s//"word_count":31/' "$tampered"
if "$BIN" diff "$CRATE/golden/standard.json" "$tampered" >"$OUT/tampered.log" 2>&1; then
  echo 'noir-ir differential accepted tampered word geometry' >&2
  exit 1
fi
grep -Fq 'NOIR_IR_DIFFERENTIAL: FAIL' "$OUT/tampered.log"
printf '%s\n' 'NOIR_IR_DIFFERENTIAL_ORACLE_V1_REGRESSION: PASS'
