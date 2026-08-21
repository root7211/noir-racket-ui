#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
TOOLCHAIN="/home/ubuntu/.rustup-noir-wgpu30/toolchains/1.87.0-x86_64-unknown-linux-gnu/bin"
export PATH="$TOOLCHAIN:$PATH"
export RUSTUP_HOME=/home/ubuntu/.rustup-noir-wgpu30
export CARGO_HOME=/home/ubuntu/.cargo-noir-wgpu30

# Application source may name a profile, but may not regain raw resource controls.
for source in examples/application-layer-workbench.rkt examples/application-layer-workbench-compact.rkt; do
  if grep -Eq '#:(logical-capacity|physical-slots|visible-rows|row-height|max-chars|data-views|state|action|transaction)' "$source"; then
    echo "application-layer source unexpectedly exposes a low-level resource/ownership form: $source" >&2
    exit 1
  fi
done

NOIR_ENTRY_MODULE=examples/application-layer-workbench.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$OUT/application-layer-workbench.scene.json" >/tmp/noir-application-dsl-standard.log 2>&1
NOIR_ENTRY_MODULE=examples/application-layer-workbench-compact.rkt PLTCOLLECTS="$ROOT:" \
  racket tools/export-dashboard.rkt "$OUT/application-layer-workbench-compact.scene.json" >/tmp/noir-application-dsl-compact.log 2>&1
python3 tools/verify_application_layer_dsl_v1.py \
  "$OUT/application-layer-workbench.scene.json" operations \
  "$OUT/application-layer-workbench-compact.scene.json" operations-compact
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >/tmp/noir-application-dsl-tests.log 2>&1
grep -Fq 'Noir Cost Model language checks passed.' /tmp/noir-application-dsl-tests.log
cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host >/tmp/noir-application-dsl-cargo.log 2>&1

DISPLAY_NUM=:767
Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 -nolisten tcp >/tmp/noir-application-dsl-xvfb.log 2>&1 &
xvfb_pid=$!
host_pid=''
cleanup() { kill "$host_pid" 2>/dev/null || true; kill "$xvfb_pid" 2>/dev/null || true; }
trap cleanup EXIT
for _ in $(seq 1 30); do [[ -S /tmp/.X11-unix/X767 ]] && break; sleep 0.1; done
DISPLAY="$DISPLAY_NUM" WGPU_BACKEND=vulkan wgpu-verify/target/release/noir_winit_host \
  "$OUT/application-layer-workbench.scene.json" >/tmp/noir-application-dsl-x11.log 2>&1 &
host_pid=$!
sleep 3
kill -0 "$host_pid"
grep -Fq 'compiler workbench cross-view transaction: v1 id=operations-acknowledge-alert-transaction action=operations-acknowledge-alert' /tmp/noir-application-dsl-x11.log
grep -Fq 'noir-winit-host:' /tmp/noir-application-dsl-x11.log
printf '%s\n' 'APPLICATION_LAYER_DSL_V1_REGRESSION: PASS'
