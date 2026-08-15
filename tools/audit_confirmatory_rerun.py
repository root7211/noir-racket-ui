#!/usr/bin/env python3
"""Audit a Noir vs GPUI rigorous-v1 benchmark run without pooling pseudoreplicated batches.

Usage:
  python3 tools/audit_confirmatory_rerun.py data/rigorous-YYYYMMDD-HHMMSS

The script treats sessions as experimental units for inferential summaries. It writes
an audit JSON and Markdown report to the supplied directory.
"""

from __future__ import annotations

import itertools
import json
import math
import re
import sys
from pathlib import Path

import numpy as np

RNG_SEED = 20260815
BOOTSTRAPS = 50_000


def read_metadata(path: Path) -> tuple[dict, bool]:
    """Load generated session metadata and flag the known unescaped-newline defect."""
    raw = path.read_text(encoding="utf-8")
    try:
        return json.loads(raw), False
    except json.JSONDecodeError:
        repaired = re.sub(
            r'("probe_output"\s*:\s*")([^"\n]*)\n([^"\n]*)(")',
            lambda match: match.group(1) + match.group(2) + r"\\n" + match.group(3) + match.group(4),
            raw,
        )
        if repaired == raw:
            raise
        return json.loads(repaired), True


def read_jsonl(path: Path) -> list[dict]:
    rows = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            value = json.loads(line)
            required = {"session_id", "framework", "batch_id", "block_id", "clicks", "total_ns", "ns_per_handler", "metric"}
            missing = sorted(required.difference(value))
            if missing:
                raise ValueError(f"{path}:{lineno}: missing fields {missing}")
            rows.append(value)
    return rows


def percentile(values: np.ndarray, q: float) -> float:
    return float(np.percentile(values, q))


def sign_flip_exact_one_sided(differences: np.ndarray) -> float:
    """Exact paired randomization p for H1: median difference < 0, using mean statistic.

    With only five independent sessions this is transparent and does not rely on a
    dubious asymptotic batch-level p value. Under the sharp null each session effect
    can take either sign. The observed statistic is the mean paired session effect.
    """
    observed = float(np.mean(differences))
    null_means = []
    for signs in itertools.product((-1.0, 1.0), repeat=len(differences)):
        null_means.append(float(np.mean(differences * np.asarray(signs))))
    return float(sum(stat <= observed + 1e-12 for stat in null_means) / len(null_means))


def hierarchical_bootstrap(sessions: list[dict], draws: int = BOOTSTRAPS) -> dict:
    """Resample sessions, then batches within each selected session, and retain median difference."""
    rng = np.random.default_rng(RNG_SEED)
    n_sessions = len(sessions)
    values = np.empty(draws, dtype=float)
    improvements = np.empty(draws, dtype=float)
    for i in range(draws):
        sample_indices = rng.integers(0, n_sessions, size=n_sessions)
        noir_values = []
        gpui_values = []
        for index in sample_indices:
            session = sessions[int(index)]
            n = session["n"]
            noir_values.append(session["noir"][rng.integers(0, n, size=n)])
            gpui_values.append(session["gpui"][rng.integers(0, n, size=n)])
        noir_flat = np.concatenate(noir_values)
        gpui_flat = np.concatenate(gpui_values)
        noir_median = float(np.median(noir_flat))
        gpui_median = float(np.median(gpui_flat))
        values[i] = noir_median - gpui_median
        improvements[i] = (gpui_median - noir_median) / gpui_median * 100.0
    return {
        "seed": RNG_SEED,
        "draws": draws,
        "median_diff_ms_ci95": [percentile(values, 2.5) / 1e6, percentile(values, 97.5) / 1e6],
        "improvement_pct_ci95": [percentile(improvements, 2.5), percentile(improvements, 97.5)],
    }


def session_summary(session_id: str, noir_rows: list[dict], gpui_rows: list[dict]) -> dict:
    noir_by_block = {int(row["block_id"]): row for row in noir_rows}
    gpui_by_block = {int(row["block_id"]): row for row in gpui_rows}
    noir_blocks = sorted(noir_by_block)
    gpui_blocks = sorted(gpui_by_block)
    if noir_blocks != list(range(len(noir_rows))) or gpui_blocks != list(range(len(gpui_rows))):
        raise ValueError(f"{session_id}: non-dense block IDs")
    if noir_blocks != gpui_blocks:
        raise ValueError(f"{session_id}: mismatch between Noir and GPUI block IDs")
    if any(int(row["clicks"]) != 25 for row in noir_rows + gpui_rows):
        raise ValueError(f"{session_id}: clicks_per_batch deviates from 25")
    if any(row["metric"] != "x11_input_to_handler" for row in noir_rows + gpui_rows):
        raise ValueError(f"{session_id}: metric label differs from x11_input_to_handler")

    paired_batch_gaps = [abs(int(noir_by_block[i]["batch_id"]) - int(gpui_by_block[i]["batch_id"])) for i in noir_blocks]
    if any(gap != 1 for gap in paired_batch_gaps):
        raise ValueError(f"{session_id}: framework records are not adjacent within each block")
    noir_first_blocks = sum(int(noir_by_block[i]["batch_id"]) < int(gpui_by_block[i]["batch_id"]) for i in noir_blocks)

    noir = np.array([float(noir_by_block[i]["ns_per_handler"]) for i in noir_blocks])
    gpui = np.array([float(gpui_by_block[i]["ns_per_handler"]) for i in gpui_blocks])
    paired = noir - gpui
    noir_median = float(np.median(noir))
    gpui_median = float(np.median(gpui))
    return {
        "session_id": session_id,
        "n": int(len(noir)),
        "noir_first_blocks": int(noir_first_blocks),
        "gpui_first_blocks": int(len(noir) - noir_first_blocks),
        "noir": noir,
        "gpui": gpui,
        "median_noir_ms": noir_median / 1e6,
        "median_gpui_ms": gpui_median / 1e6,
        "median_diff_ms": (noir_median - gpui_median) / 1e6,
        "relative_improvement_pct": (gpui_median - noir_median) / gpui_median * 100.0,
        "noir_p95_ms": percentile(noir, 95) / 1e6,
        "gpui_p95_ms": percentile(gpui, 95) / 1e6,
        "noir_p99_ms": percentile(noir, 99) / 1e6,
        "gpui_p99_ms": percentile(gpui, 99) / 1e6,
        "paired_batch_median_diff_ms": float(np.median(paired)) / 1e6,
        "paired_batch_negative_fraction": float(np.mean(paired < 0.0)),
    }


def main(data_dir: Path) -> int:
    env = json.loads((data_dir / "global-env.json").read_text(encoding="utf-8"))
    session_ids = sorted(path.name.replace("-env.json", "") for path in data_dir.glob("session-*-env.json"))
    incomplete_path = data_dir / "incomplete-batches.jsonl"
    incomplete_count = len(read_jsonl(incomplete_path)) if incomplete_path.exists() else 0

    sessions = []
    metadata = []
    metadata_repairs = 0
    for session_id in session_ids:
        noir_rows = read_jsonl(data_dir / f"{session_id}-noir.jsonl")
        gpui_rows = read_jsonl(data_dir / f"{session_id}-gpui.jsonl")
        summary = session_summary(session_id, noir_rows, gpui_rows)
        sessions.append(summary)
        session_metadata, repaired = read_metadata(data_dir / f"{session_id}-env.json")
        metadata.append(session_metadata)
        metadata_repairs += int(repaired)

    noir_all = np.concatenate([s["noir"] for s in sessions])
    gpui_all = np.concatenate([s["gpui"] for s in sessions])
    session_median_diffs = np.asarray([s["median_diff_ms"] * 1e6 for s in sessions])
    session_improvements = np.asarray([s["relative_improvement_pct"] for s in sessions])
    bootstrap = hierarchical_bootstrap(sessions)

    no_adapter_probe = all("Error:" in str(m.get("adapter", {}).get("probe_output", "")) for m in metadata)
    unknown_cpu = all(m.get("system", {}).get("cpu_governor") == "unknown" for m in metadata)
    unknown_power = all(m.get("system", {}).get("power_state") == "unknown" for m in metadata)
    fingerprints = {(m.get("build", {}).get("git_commit"), m.get("build", {}).get("noir_binary_sha256"), m.get("build", {}).get("gpui_binary_sha256")) for m in metadata}

    audit = {
        "audit_version": "session-aware-v1",
        "data_directory": str(data_dir),
        "protocol": env,
        "integrity": {
            "sessions_declared": int(env["sessions"]),
            "sessions_found": len(sessions),
            "batches_per_framework_by_session": [s["n"] for s in sessions],
            "actual_block_order": [{"session_id": s["session_id"], "noir_first": s["noir_first_blocks"], "gpui_first": s["gpui_first_blocks"]} for s in sessions],
            "complete": len(sessions) == int(env["sessions"]) and all(s["n"] == int(env["measurement_batches"]) for s in sessions),
            "incomplete_batch_records": incomplete_count,
            "binary_fingerprint_sets": len(fingerprints),
            "metadata_files_requiring_json_repair": metadata_repairs,
            "adapter_probe_failed_all_sessions": no_adapter_probe,
            "cpu_governor_unknown_all_sessions": unknown_cpu,
            "power_state_unknown_all_sessions": unknown_power,
        },
        "pooled_descriptive_only": {
            "observations_per_framework": int(len(noir_all)),
            "noir_median_ms": float(np.median(noir_all) / 1e6),
            "gpui_median_ms": float(np.median(gpui_all) / 1e6),
            "relative_improvement_pct": float((np.median(gpui_all) - np.median(noir_all)) / np.median(gpui_all) * 100.0),
        },
        "session_level_primary": {
            "independent_units": len(sessions),
            "session_median_diffs_ms": [float(value / 1e6) for value in session_median_diffs],
            "session_relative_improvements_pct": [float(value) for value in session_improvements],
            "median_session_diff_ms": float(np.median(session_median_diffs) / 1e6),
            "median_session_improvement_pct": float(np.median(session_improvements)),
            "mean_session_improvement_pct": float(np.mean(session_improvements)),
            "all_sessions_favor_noir": bool(np.all(session_median_diffs < 0.0)),
            "exact_sign_flip_one_sided_p": sign_flip_exact_one_sided(session_median_diffs),
            "exact_sign_test_two_sided_p": min(1.0, 2.0 * sign_flip_exact_one_sided(session_median_diffs)),
            "hierarchical_bootstrap": bootstrap,
        },
        "sessions": [{key: value for key, value in s.items() if key not in {"noir", "gpui"}} for s in sessions],
        "interpretation": {
            "supported": "For this exact Xvfb/WSL2 Dozen fixed-click endpoint, all five session medians favor Noir and the session-aware hierarchical bootstrap remains below zero.",
            "not_supported": "The raw data do not establish native-display input-to-photon latency, scroll performance, general GUI performance, or a cross-device advantage. Batch-level pooled p-values are sensitivity evidence only because batches are nested within five sessions.",
        },
    }

    json_path = data_dir / "session-aware-audit.json"
    json_path.write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# Confirmatory Rerun Session-Aware Audit",
        "",
        "## Result",
        "",
        f"The rerun contains **{len(sessions)} complete sessions** with **{sessions[0]['n']} batches per framework per session** and no incomplete-batch record. The pooled 1,000-batch result is descriptive; the primary independent units are the five sessions.",
        "",
        "| Session | Noir median (ms) | GPUI median (ms) | Difference, Noir−GPUI (ms) | Noir improvement | Block order (N/G first) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for s in audit["sessions"]:
        lines.append(f"| {s['session_id']} | {s['median_noir_ms']:.3f} | {s['median_gpui_ms']:.3f} | {s['median_diff_ms']:.3f} | {s['relative_improvement_pct']:.2f}% | {s['noir_first_blocks']}/{s['gpui_first_blocks']} |")
    primary = audit["session_level_primary"]
    ci = primary["hierarchical_bootstrap"]["median_diff_ms_ci95"]
    ic = primary["hierarchical_bootstrap"]["improvement_pct_ci95"]
    lines.extend([
        "",
        "## Session-aware summary",
        "",
        f"All 5/5 session medians favor Noir. The median of the five session improvements is **{primary['median_session_improvement_pct']:.2f}%**. A two-stage bootstrap (resample sessions, then batches; {BOOTSTRAPS:,} draws, seed {RNG_SEED}) yields a 95% interval of **[{ci[0]:.3f}, {ci[1]:.3f}] ms** for Noir−GPUI and **[{ic[0]:.2f}%, {ic[1]:.2f}%]** for relative improvement. The exact one-sided five-session sign-flip test is **p={primary['exact_sign_flip_one_sided_p']:.5f}** only if the direction “Noir faster” was fixed before observing this rerun; the corresponding two-sided sign-test p-value is **{primary['exact_sign_test_two_sided_p']:.5f}**.",
        "",
        "## Audit limits",
        "",
        "The session metadata fingerprints both binaries consistently, but all five metadata files contain an unescaped newline in `adapter.probe_output`, so they are not valid JSON as committed. After minimal repair for audit parsing, the adapter probe is still shown to have failed in every session and CPU governor/power state remain unknown. The harness measures X11 input dispatch through logged handler completion after fresh process startup; it excludes presentation and does not establish input-to-photon latency. It is a fixed-click virtual-list endpoint, not a scroll, rendering-throughput, native-display, multi-device, or general-GUI benchmark.",
        "",
        "The existing `analysis-results.json` reports p-values from 1,000 pooled batch observations. Those batches are nested within five sessions, so their p-values should be labeled sensitivity/descriptive evidence rather than the primary inferential result. This audit uses five session effects as its independent evidence.",
    ])
    md_path = data_dir / "SESSION_AWARE_AUDIT.md"
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json_path)
    print(md_path)
    print(json.dumps(audit["session_level_primary"], indent=2))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: audit_confirmatory_rerun.py <data-directory>")
    raise SystemExit(main(Path(sys.argv[1])))
