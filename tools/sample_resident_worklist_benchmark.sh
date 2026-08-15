#!/usr/bin/env bash
# Run independent real wgpu benchmark processes for a stable before/after comparison.
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <binary> <scene> <iterations> <output-jsonl>" >&2
  exit 64
fi

BINARY=$1
SCENE=$2
ITERATIONS=$3
OUTPUT=$4
: "${DISPLAY:?DISPLAY must point to a running X11 server}"
: "${WGPU_BACKEND:=vulkan}"
: "${XDG_RUNTIME_DIR:=/tmp}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
: > "$OUTPUT"
for iteration in $(seq 1 "$ITERATIONS"); do
  REPORT="$TMPDIR/report-$iteration.json"
  "$BINARY" "$SCENE" --benchmark-report "$REPORT" >"$TMPDIR/run-$iteration.log" 2>&1
  jq --argjson iteration "$iteration" '.cases[] | {iteration: $iteration, id, cpu_event_to_submit_ns, gpu_elapsed_ns, expectations_match}' "$REPORT" >> "$OUTPUT"
done
