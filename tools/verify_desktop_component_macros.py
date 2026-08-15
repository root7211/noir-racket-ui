#!/usr/bin/env python3
"""Prove desktop component macros vanish into the pre-existing Scene representation."""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

COMPONENT_TAGS = {
    "app-shell",
    "surface",
    "toolbar",
    "table-header",
    "status-pill",
    "detail-panel",
}
# Build attestation intentionally incorporates source/compiler fingerprints; macro migration
# changes those provenance values while the runtime Scene must remain identical.
IGNORED_KEYS = {"source_fingerprint", "source", "source_path", "build_attestation"}


def normalize(value):
    if isinstance(value, dict):
        return {
            key: normalize(child)
            for key, child in value.items()
            if key not in IGNORED_KEYS
        }
    if isinstance(value, list):
        return [normalize(child) for child in value]
    return value


def find_component_tags(value, path="$"):
    found = []
    if isinstance(value, dict):
        tag = value.get("tag")
        if tag in COMPONENT_TAGS:
            found.append((path, tag))
        for key, child in value.items():
            found.extend(find_component_tags(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(find_component_tags(child, f"{path}[{index}]"))
    return found


def compact_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def first_difference(left, right, path="$"):
    if type(left) is not type(right):
        return path, left, right
    if isinstance(left, dict):
        left_keys, right_keys = set(left), set(right)
        if left_keys != right_keys:
            return f"{path}.keys", sorted(left_keys), sorted(right_keys)
        for key in sorted(left_keys):
            diff = first_difference(left[key], right[key], f"{path}.{key}")
            if diff:
                return diff
        return None
    if isinstance(left, list):
        if len(left) != len(right):
            return f"{path}.length", len(left), len(right)
        for index, (left_item, right_item) in enumerate(zip(left, right)):
            diff = first_difference(left_item, right_item, f"{path}[{index}]")
            if diff:
                return diff
        return None
    if left != right:
        return path, left, right
    return None


def main() -> int:
    arguments = sys.argv[1:]
    if len(arguments) < 3 or len(arguments) % 3 != 0:
        raise SystemExit(
            "usage: verify_desktop_component_macros.py "
            "<baseline-name> <baseline.scene.json> <macro.scene.json> [...]"
        )
    triples = [
        (arguments[index], Path(arguments[index + 1]), Path(arguments[index + 2]))
        for index in range(0, len(arguments), 3)
    ]
    for name, baseline_path, component_path in triples:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        component = json.loads(component_path.read_text(encoding="utf-8"))
        tags = find_component_tags(component)
        if tags:
            raise SystemExit(f"{name}: component tags leaked into runtime Scene: {tags}")
        normalized_baseline = normalize(copy.deepcopy(baseline))
        normalized_component = normalize(copy.deepcopy(component))
        if normalized_baseline != normalized_component:
            difference = first_difference(normalized_baseline, normalized_component)
            raise SystemExit(
                f"{name}: inline Scene differs from primitive baseline after removing only source fingerprint metadata\n"
                f"first_difference={difference}\n"
                f"baseline={compact_json(normalized_baseline)[:300]}\n"
                f"component={compact_json(normalized_component)[:300]}"
            )
        print(f"desktop-component-equivalence: {name}: PASS")
    print("desktop component macros: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
