#!/usr/bin/env python3
"""Render a compact visual summary from session-aware-audit.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def main(audit_path: Path, output_path: Path) -> int:
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    sessions = audit["sessions"]
    labels = [item["session_id"].replace("session-", "S") for item in sessions]
    noir = np.asarray([item["median_noir_ms"] for item in sessions])
    gpui = np.asarray([item["median_gpui_ms"] for item in sessions])
    improvement = np.asarray([item["relative_improvement_pct"] for item in sessions])
    x = np.arange(len(labels))

    plt.style.use("seaborn-v0_8-whitegrid")
    figure, (left, right) = plt.subplots(1, 2, figsize=(11.5, 4.6), gridspec_kw={"width_ratios": [1.25, 1]})
    width = 0.34
    left.bar(x - width / 2, noir, width, label="Noir", color="#2f6fed")
    left.bar(x + width / 2, gpui, width, label="GPUI", color="#f29d38")
    left.set_xticks(x, labels)
    left.set_ylabel("Median X11 input → handler latency (ms)")
    left.set_title("Five independent sessions")
    left.legend(frameon=False, loc="upper left")
    left.set_ylim(0, max(gpui) * 1.18)
    for position, value in zip(x - width / 2, noir):
        left.text(position, value + 0.018, f"{value:.3f}", ha="center", va="bottom", fontsize=8, color="#1649a4")
    for position, value in zip(x + width / 2, gpui):
        left.text(position, value + 0.018, f"{value:.3f}", ha="center", va="bottom", fontsize=8, color="#9c5c09")

    bars = right.bar(labels, improvement, color="#237a57")
    right.axhline(float(np.median(improvement)), color="#173f33", linestyle="--", linewidth=1.4, label=f"Median {np.median(improvement):.2f}%")
    right.set_ylabel("Noir improvement vs GPUI (%)")
    right.set_title("Session-level effect consistency")
    right.set_ylim(0, 55)
    right.legend(frameon=False, loc="lower right")
    for bar, value in zip(bars, improvement):
        right.text(bar.get_x() + bar.get_width() / 2, value + 0.7, f"{value:.1f}%", ha="center", va="bottom", fontsize=8, color="#154a35")

    figure.suptitle("Noir vs GPUI — AMD 780M / WSL2 Dozen / Xvfb fixed-click endpoint", fontsize=13, fontweight="bold", y=1.03)
    figure.text(0.5, -0.02, "Session is the independent unit; values are per-session medians (n = 5).", ha="center", fontsize=9, color="#46505a")
    figure.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(figure)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: plot_session_aware_audit.py <audit-json> <output-png>")
    raise SystemExit(main(Path(sys.argv[1]), Path(sys.argv[2])))
