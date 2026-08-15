#!/usr/bin/env python3
"""
analyze_rigorous_benchmark.py - 统计学正确的分析

使用配对分析、Hodges-Lehmann 估计、Bootstrap CI 和 TOST 等效检验
"""

import json
import sys
from pathlib import Path
import numpy as np
from scipy import stats

def load_session_data(data_dir, session_id, framework):
    """加载单个 session 的数据"""
    file = Path(data_dir) / f"{session_id}-{framework}.jsonl"
    if not file.exists():
        return None
    
    batches = []
    for line in file.read_text().splitlines():
        if line.strip():
            data = json.loads(line)
            batches.append(data['ns_per_handler'])
    return np.array(batches)

def hodges_lehmann_estimator(x, y):
    """配对差值的中位数"""
    return np.median(x - y)

def bootstrap_ci(x, y, func, n_bootstrap=10000, alpha=0.05):
    """Bootstrap 置信区间"""
    n = len(x)
    estimates = []
    np.random.seed(42)
    for _ in range(n_bootstrap):
        idx = np.random.choice(n, n, replace=True)
        estimates.append(func(x[idx], y[idx]))
    estimates = np.array(estimates)
    return np.percentile(estimates, [alpha/2*100, (1-alpha/2)*100])

def tost_equivalence(x, y, equiv_margin_pct=5, alpha=0.05):
    """TOST 等效检验（基于相对差异百分比）"""
    median_y = np.median(y)
    lower = -equiv_margin_pct/100 * median_y
    upper = equiv_margin_pct/100 * median_y
    
    diff = x - y
    # Test H0: diff <= lower
    t1, p1 = stats.ttest_1samp(diff - lower, 0, alternative='greater')
    # Test H0: diff >= upper  
    t2, p2 = stats.ttest_1samp(diff - upper, 0, alternative='less')
    return max(p1, p2)

def main(data_dir):
    data_dir = Path(data_dir)
    
    # 加载全局环境
    global_env = json.loads((data_dir / "global-env.json").read_text())
    print("=" * 70)
    print("Rigorous Benchmark Analysis")
    print("=" * 70)
    print(f"Protocol: {global_env['protocol_version']}")
    print(f"Sessions: {global_env['sessions']}")
    print(f"Warmup: {global_env['warmup_batches']} batches")
    print(f"Measurement: {global_env['measurement_batches']} batches per framework")
    print(f"Total observations: {global_env['total_observations_per_framework']} per framework")
    print()
    
    # 查找所有 session
    sessions = sorted([f.stem.replace("-env", "") 
                      for f in data_dir.glob("session-*-env.json")])
    
    if not sessions:
        print("ERROR: No session data found")
        return 1
    
    print(f"Found {len(sessions)} sessions: {', '.join(sessions)}")
    print()
    
    # 加载所有数据
    noir_sessions = []
    gpui_sessions = []
    
    for session_id in sessions:
        noir_data = load_session_data(data_dir, session_id, "noir")
        gpui_data = load_session_data(data_dir, session_id, "gpui")
        
        if noir_data is None or gpui_data is None:
            print(f"WARNING: Incomplete data for {session_id}")
            continue
        
        # 对齐数据（取较短长度）
        min_len = min(len(noir_data), len(gpui_data))
        noir_sessions.append(noir_data[:min_len])
        gpui_sessions.append(gpui_data[:min_len])
        
        print(f"{session_id}: noir={len(noir_data)} batches, gpui={len(gpui_data)} batches (using {min_len})")
    
    print()
    
    if len(noir_sessions) == 0:
        print("ERROR: No valid session data")
        return 1
    
    # 合并所有 session
    noir_all = np.concatenate(noir_sessions)
    gpui_all = np.concatenate(gpui_sessions)
    
    print("=" * 70)
    print("Statistical Analysis")
    print("=" * 70)
    
    # 基本统计
    median_noir = np.median(noir_all)
    median_gpui = np.median(gpui_all)
    mean_noir = np.mean(noir_all)
    mean_gpui = np.mean(gpui_all)
    
    print(f"\n[Descriptive Statistics]")
    print(f"Noir:")
    print(f"  Median: {median_noir/1e6:.3f} ms")
    print(f"  Mean:   {mean_noir/1e6:.3f} ms")
    print(f"  Std:    {np.std(noir_all)/1e6:.3f} ms")
    print(f"  P95:    {np.percentile(noir_all, 95)/1e6:.3f} ms")
    print(f"  P99:    {np.percentile(noir_all, 99)/1e6:.3f} ms")
    
    print(f"\nGPUI:")
    print(f"  Median: {median_gpui/1e6:.3f} ms")
    print(f"  Mean:   {mean_gpui/1e6:.3f} ms")
    print(f"  Std:    {np.std(gpui_all)/1e6:.3f} ms")
    print(f"  P95:    {np.percentile(gpui_all, 95)/1e6:.3f} ms")
    print(f"  P99:    {np.percentile(gpui_all, 99)/1e6:.3f} ms")
    
    # Hodges-Lehmann 估计
    hl_diff = hodges_lehmann_estimator(noir_all, gpui_all)
    ci = bootstrap_ci(noir_all, gpui_all, hodges_lehmann_estimator)
    
    relative_improvement = (median_gpui - median_noir) / median_gpui * 100
    
    print(f"\n[Effect Size Estimation]")
    print(f"Hodges-Lehmann difference: {hl_diff/1e6:.3f} ms")
    print(f"  95% Bootstrap CI: [{ci[0]/1e6:.3f}, {ci[1]/1e6:.3f}] ms")
    print(f"Relative improvement: {relative_improvement:.1f}%")
    print(f"  GPUI median - Noir median = {(median_gpui - median_noir)/1e6:.3f} ms")
    
    # Session 方向一致性
    session_favors_noir = sum(
        np.median(noir) < np.median(gpui)
        for noir, gpui in zip(noir_sessions, gpui_sessions)
    )
    
    print(f"\n[Session Consistency]")
    print(f"Sessions favoring Noir: {session_favors_noir}/{len(sessions)}")
    for i, (noir, gpui) in enumerate(zip(noir_sessions, gpui_sessions), 1):
        diff_pct = (np.median(gpui) - np.median(noir)) / np.median(gpui) * 100
        winner = "Noir" if np.median(noir) < np.median(gpui) else "GPUI"
        print(f"  Session {i}: {winner} (Noir {np.median(noir)/1e6:.3f} ms vs GPUI {np.median(gpui)/1e6:.3f} ms, {diff_pct:+.1f}%)")
    
    # 配对检验
    print(f"\n[Hypothesis Testing]")
    
    # Wilcoxon 符号秩检验
    wilcoxon_result = stats.wilcoxon(noir_all - gpui_all, alternative='less')
    print(f"Wilcoxon signed-rank test (H1: Noir < GPUI):")
    print(f"  p-value: {wilcoxon_result.pvalue:.6f}")
    
    # 配对 t 检验（参数）
    t_result = stats.ttest_rel(noir_all, gpui_all, alternative='less')
    print(f"Paired t-test (H1: Noir < GPUI):")
    print(f"  p-value: {t_result.pvalue:.6f}")
    
    # TOST 等效检验
    tost_p = tost_equivalence(noir_all, gpui_all, equiv_margin_pct=5)
    print(f"\nTOST equivalence test (margin = ±5%):")
    print(f"  p-value: {tost_p:.6f}")
    
    # 结论
    print(f"\n" + "=" * 70)
    print("Conclusion")
    print("=" * 70)
    
    ci_excludes_zero = ci[1] < 0
    session_consistent = session_favors_noir >= max(3, len(sessions) * 0.8)
    practical_threshold = abs(relative_improvement) >= 10
    
    if ci_excludes_zero and session_consistent and practical_threshold:
        print("✓ SIGNIFICANT AND PRACTICALLY MEANINGFUL")
        print(f"  - 95% CI excludes zero: {ci_excludes_zero}")
        print(f"  - Session consistency: {session_favors_noir}/{len(sessions)} (≥80%: {session_consistent})")
        print(f"  - Meets practical threshold (≥10%): {practical_threshold} ({relative_improvement:.1f}%)")
        conclusion = "significant_meaningful"
    elif abs(relative_improvement) < 5 and ci[0]/median_gpui > -0.05 and ci[1]/median_gpui < 0.05:
        print("≈ STATISTICALLY EQUIVALENT")
        print(f"  - Relative difference: {relative_improvement:.1f}% (< 5%)")
        print(f"  - 95% CI within ±5% range")
        conclusion = "equivalent"
    else:
        print("? INSUFFICIENT EVIDENCE")
        print(f"  - CI excludes zero: {ci_excludes_zero}")
        print(f"  - Session consistency: {session_favors_noir}/{len(sessions)}")
        print(f"  - Practical threshold: {practical_threshold} ({relative_improvement:.1f}%)")
        conclusion = "insufficient"
    
    # 保存结果
    results = {
        "protocol": global_env["protocol_version"],
        "sessions": len(sessions),
        "total_observations": len(noir_all),
        "noir": {
            "median_ms": float(median_noir / 1e6),
            "mean_ms": float(mean_noir / 1e6),
            "std_ms": float(np.std(noir_all) / 1e6),
            "p95_ms": float(np.percentile(noir_all, 95) / 1e6),
            "p99_ms": float(np.percentile(noir_all, 99) / 1e6)
        },
        "gpui": {
            "median_ms": float(median_gpui / 1e6),
            "mean_ms": float(mean_gpui / 1e6),
            "std_ms": float(np.std(gpui_all) / 1e6),
            "p95_ms": float(np.percentile(gpui_all, 95) / 1e6),
            "p99_ms": float(np.percentile(gpui_all, 99) / 1e6)
        },
        "effect_size": {
            "hodges_lehmann_diff_ms": float(hl_diff / 1e6),
            "bootstrap_ci_95_ms": [float(ci[0] / 1e6), float(ci[1] / 1e6)],
            "relative_improvement_pct": float(relative_improvement)
        },
        "hypothesis_tests": {
            "wilcoxon_p": float(wilcoxon_result.pvalue),
            "paired_t_p": float(t_result.pvalue),
            "tost_equivalence_p": float(tost_p)
        },
        "session_consistency": {
            "favoring_noir": int(session_favors_noir),
            "total_sessions": len(sessions)
        },
        "conclusion": conclusion
    }
    
    output_file = data_dir / "analysis-results.json"
    output_file.write_text(json.dumps(results, indent=2))
    print(f"\nResults saved to: {output_file}")
    
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: analyze_rigorous_benchmark.py <data_dir>")
        sys.exit(1)
    
    sys.exit(main(sys.argv[1]))
