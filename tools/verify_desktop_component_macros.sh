#!/usr/bin/env bash
# Desktop component macros are compile-time syntax compression. This oracle proves a
# hand-written primitive fixture and its macro counterpart export the same runtime Scene.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d /tmp/noir-desktop-components.XXXXXX)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

cd "$ROOT"
PLTCOLLECTS="$ROOT:" racket tests/run.rkt >"$TMP/racket.log" 2>&1
grep -F 'Noir Cost Model language checks passed.' "$TMP/racket.log"

export_scene() {
  local module=$1
  local output=$2
  NOIR_ENTRY_MODULE="$module" PLTCOLLECTS="$ROOT:" \
    racket tools/export-dashboard.rkt "$output" >"$TMP/$(basename "$module").log" 2>&1
}

export_scene examples/desktop-components-primitive.rkt "$TMP/primitive.scene.json"
export_scene examples/desktop-components-macros.rkt "$TMP/macros.scene.json"
python3 tools/verify_desktop_component_macros.py \
  fixture "$TMP/primitive.scene.json" "$TMP/macros.scene.json"

echo "desktop component macro regression: PASS"
