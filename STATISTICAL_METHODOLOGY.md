# Noir vs GPUI 统计学实验设计

## 当前测量的严重缺陷

### ❌ 错误：将相关观测当作独立样本

**当前错误做法**:
- 15 samples × 25 clicks = 375 "独立"事件
- 直接计算 375 个数据点的中位数和标准差
- **问题**: 同一个 25-click batch 内的事件高度相关（同一进程、同一调度窗口、同一缓存状态）

**正确理解**:
- **一个 25-click batch 只能算作一个样本**
- 当前实际只有 **15 个独立观测** per framework
- 15 个样本远不足以建立统计学意义

---

## 正确的实验设计

### 1. 实验单位与随机化

| 层级 | 最低要求 | 推荐标准 | 作用 |
|------|----------|----------|------|
| **预热 batch** | 30 个完整 batch | 50-100 个完整 batch | 排除 pipeline、atlas、缓存、频率爬升 |
| **独立 session** | 3 个 | **5 个**（每次重启两框架） | 对抗进程状态、WSL/Dozen、温度、scheduler 漂移 |
| **每 session 每框架** | 50 个 batch | **200 个 batch** | 每个 session 的中位数、P95、P99 |
| **总独立观测** | 150 | **1,000 / framework / workload** | 5 session × 200 batch |
| **运行顺序** | 交替 | **随机化 + 区组化交替** | 防止"总是先运行 Noir/GPUI"的偏置 |

### 2. 采集协议

#### A. 每个 session 的执行流程

```bash
# Session N (N = 1..5)
SESSION_ID="session-$(date +%Y%m%d-%H%M%S)"

# 1. 预热（丢弃数据）
for i in {1..50}; do
  run_noir_batch 25  # 不记录
  run_gpui_batch 25  # 不记录
done

# 2. 正式采集（200 个 batch，随机顺序）
ORDER=$(shuf -e $(printf "noir\ngpui\n%.0s" {1..100}))
for framework in $ORDER; do
  run_${framework}_batch 25 >> data/${SESSION_ID}-${framework}.jsonl
done

# 3. 记录环境
cat > data/${SESSION_ID}-env.json << EOF
{
  "session_id": "$SESSION_ID",
  "gpu": "AMD 780M",
  "driver": "Mesa Dozen 26.1.7",
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)",
  "timestamp_period_ns": $(get_timestamp_period),
  "wgpu_backend": "$WGPU_BACKEND",
  "warm_up_batches": 50,
  "measurement_batches": 200,
  "clicks_per_batch": 25
}
EOF
```

#### B. 数据格式

每个 batch 记录为一行：

```json
{
  "session_id": "session-20260815-190000",
  "framework": "noir",
  "batch_id": 42,
  "clicks": 25,
  "total_ns": 16789450,
  "ns_per_handler": 671578.0,
  "metric": "x11_input_to_handler"
}
```

**关键**: `ns_per_handler` 是该 batch 的平均值，**不是 25 个独立观测**。

---

## 3. 统计分析方法

### A. Click Handler Endpoint（有方向性假设）

**假设**: Noir 比 GPUI 快

**分析流程**:

1. **配对数据**
   - 每个 session 内，按 batch_id 配对（Noir batch N vs GPUI batch N）
   - 计算配对差值: `diff = noir_ns - gpui_ns`

2. **效应量估计**
   - Hodges-Lehmann 估计（配对差值的中位数）
   - 相对改善: `(median_gpui - median_noir) / median_gpui * 100%`

3. **置信区间**
   - 95% bootstrap 置信区间（10,000 次重采样）
   - 基于 session 层级的区组 bootstrap

4. **假设检验**
   - 配对符号检验（非参数）
   - Wilcoxon 符号秩检验
   - 要求: 至少 4/5 个 session 方向一致

5. **实际意义阈值**
   - 预注册阈值: **中位数改善 ≥ 10%**
   - 只有同时满足统计显著性 + 实际阈值，才称"有统计与实际意义"

**报告模板**:

```
Click Handler Endpoint (Noir vs GPUI):
  
  Noir 中位数:     0.XX ms  [95% CI: 0.XX–0.XX]
  GPUI 中位数:     0.XX ms  [95% CI: 0.XX–0.XX]
  Hodges-Lehmann 差: -0.XX ms  [95% CI: -0.XX to -0.XX]
  相对改善:        XX.X%  [95% CI: XX%–XX%]
  
  Session 方向一致性: 5/5 sessions favor Noir
  配对符号检验:     p < 0.001
  
  结论: ✓ 显著且实际有意义（改善 > 10%，CI 不跨零）
```

### B. Scroll Endpoint（等效性检验）

**当前观察**: 中位数只差 ~0.11%

**正确目标**: 证明等效，而非"没有显著差异"

**分析流程**:

1. **预定义等效区间**
   - 例如: ±5% 相对差异
   - 或: ±0.5 ms 绝对差异

2. **TOST (Two One-Sided Tests)**
   - H₀: |Noir - GPUI| ≥ 等效界限
   - H₁: |Noir - GPUI| < 等效界限
   - 只有当 95% CI 完全落在等效区间内，才能声称等效

3. **P95/P99 尾延迟分析**
   - **按 session 独立汇总**（不是跨 session 混合）
   - 报告每个 session 的 P95/P99
   - 异常值需要单独诊断（例如 GPUI 的 36 ms 峰值）

**报告模板**:

```
Scroll Endpoint (Noir vs GPUI):
  
  Noir 中位数:     X.XX ms  [95% CI: X.XX–X.XX]
  GPUI 中位数:     X.XX ms  [95% CI: X.XX–X.XX]
  相对差异:        0.XX%  [95% CI: -X%–X%]
  
  等效检验 (±5%):  95% CI 完全落在 [-5%, +5%] 内
  TOST p-value:    p = 0.XXX
  
  P95 (5 sessions): Noir [X.X, X.X, X.X, X.X, X.X] ms
                    GPUI [X.X, X.X, X.X, X.X, X.X] ms
  
  结论: ✓ 统计等效（在 ±5% 区间内）
        ⚠ GPUI 在 2/5 sessions 出现 >30ms 尾延迟，需诊断
```

---

## 4. GPU Timestamp 的独立采集

### 与 X11 Endpoint 分离

**错误做法**: 将 X11 延迟 + GPU timestamp 混为"总延迟"

**正确做法**: 独立采集和报告

### GPU Command Region 采集协议

```bash
# 每个 Scene、每个 session: 200 次有效 timestamp 观测
for session in {1..5}; do
  # 预热 50 次
  for i in {1..50}; do
    run_scene_with_timestamp  # 不记录
  done
  
  # 采集 200 次
  for i in {1..200}; do
    RESULT=$(run_scene_with_timestamp)
    echo "$RESULT" >> gpu-timestamps-session${session}.jsonl
  done
done
```

### 必须记录的元数据

```json
{
  "scene": "data-register-table-10000",
  "session_id": "session-5",
  "sample_id": 123,
  "gpu_elapsed_ns": 44520.0,
  "cpu_submit_ns": 12102212,
  "timestamp_period_ns": 10.0,
  "adapter": "AMD 780M",
  "driver": "Mesa Dozen 26.1.7",
  "cpu_governor": "performance",
  "power_state": "AC",
  "dozen_version": "26.1.7",
  "tiles_submitted": 2,
  "glyph_instances": 3
}
```

### GPU vs CPU 必须分开检验

- **GPU command region**: `gpu_elapsed_ns` (物理 GPU 执行时间)
- **CPU event-to-submit**: `cpu_submit_ns` (CPU 路径开销)
- **不要混合**: 它们测量不同的系统层级

---

## 5. 结论标签体系

### 三种标准化结论

| 标签 | 条件 | 示例 |
|------|------|------|
| **✓ 显著且实际有意义** | 1. 95% CI 不跨零<br>2. ≥4/5 session 方向一致<br>3. 效应 ≥ 预注册阈值 | Click handler: Noir 快 51% [CI: 45%–58%] |
| **≈ 统计等效** | 95% CI 完全落在预定义等效区间内 | Scroll: 差异 0.1% [CI: -2%–3%]，等效于 ±5% |
| **? 证据不足** | CI 跨零或跨等效界限 | 当前 15 样本的大多数指标 |

---

## 6. 当前数据的正确评估

### Click Handler Endpoint

**状态**: ✓ 强候选，但需正式确认

- 当前观察: Noir 0.67 ms vs GPUI 1.38 ms (快 51%)
- **问题**: 只有 15 个独立观测（不是 375 个）
- **下一步**: 执行完整的 5 session × 200 batch 协议

### Scroll Endpoint

**状态**: ≈ 可能等效，需正式验证

- 当前观察: 差异 ~0.11%
- **目标**: 等效检验，而非"Noir 获胜"
- **关注点**: GPUI 的 2 个 36 ms 尾延迟需诊断

### GPU Timestamp

**状态**: ? 单次运行，不足以下结论

- 当前观察: ~45 μs
- **问题**: 没有跨 session 重复、没有方差估计
- **下一步**: 独立采集 5 × 200 样本

---

## 7. 推荐的发布清单

### 最低标准（可发布）

- [ ] 3 个独立 session
- [ ] 每 session 50 个预热 + 50 个测量 batch
- [ ] 配对分析 + bootstrap CI
- [ ] 报告所有三类结论标签
- [ ] 原始 JSONL 数据公开

### 推荐标准（高质量）

- [ ] **5 个独立 session**
- [ ] 每 session **50 个预热 + 200 个测量** batch
- [ ] 随机化 + 区组化运行顺序
- [ ] Hodges-Lehmann 估计 + TOST 等效检验
- [ ] 按 session 独立报告 P95/P99
- [ ] GPU timestamp 独立采集（5 × 200）
- [ ] 完整环境元数据（CPU governor, 温度, 电源）
- [ ] 预注册实际意义阈值

---

## 8. 实现脚本框架

```bash
#!/bin/bash
# rigorous_benchmark.sh - 统计学正确的基准测试

set -euo pipefail

SESSIONS=5
WARMUP_BATCHES=50
MEASUREMENT_BATCHES=200
CLICKS_PER_BATCH=25
OUTPUT_DIR="data/rigorous-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUTPUT_DIR"

for session in $(seq 1 $SESSIONS); do
  SESSION_ID="session-${session}"
  echo "=== Starting $SESSION_ID ==="
  
  # 预热
  echo "Warming up ($WARMUP_BATCHES batches)..."
  for i in $(seq 1 $WARMUP_BATCHES); do
    run_noir_batch $CLICKS_PER_BATCH >/dev/null
    run_gpui_batch $CLICKS_PER_BATCH >/dev/null
  done
  
  # 生成随机顺序
  ORDER=$(python3 -c "
import random
frameworks = ['noir', 'gpui'] * $MEASUREMENT_BATCHES
random.shuffle(frameworks)
print(' '.join(frameworks))
")
  
  # 正式采集
  echo "Collecting measurements ($MEASUREMENT_BATCHES batches per framework)..."
  batch_id=0
  for framework in $ORDER; do
    RESULT=$(run_${framework}_batch $CLICKS_PER_BATCH)
    echo "{\"session_id\":\"$SESSION_ID\",\"batch_id\":$batch_id,\"framework\":\"$framework\",$RESULT}" \
      >> "$OUTPUT_DIR/${SESSION_ID}-${framework}.jsonl"
    ((batch_id++))
  done
  
  # 记录环境
  save_environment_metadata "$OUTPUT_DIR/${SESSION_ID}-env.json"
  
  echo "=== Completed $SESSION_ID ==="
  sleep 60  # session 间冷却
done

# 统计分析
python3 analyze_rigorous_benchmark.py "$OUTPUT_DIR"
```

---

## 9. 分析脚本示例

```python
#!/usr/bin/env python3
"""
analyze_rigorous_benchmark.py - 统计学正确的分析
"""

import json
import numpy as np
from scipy import stats
from pathlib import Path

def hodges_lehmann_estimator(x, y):
    """配对差值的中位数"""
    return np.median(x - y)

def bootstrap_ci(x, y, func, n_bootstrap=10000, alpha=0.05):
    """Bootstrap 置信区间"""
    n = len(x)
    estimates = []
    for _ in range(n_bootstrap):
        idx = np.random.choice(n, n, replace=True)
        estimates.append(func(x[idx], y[idx]))
    return np.percentile(estimates, [alpha/2*100, (1-alpha/2)*100])

def tost_equivalence(x, y, lower, upper, alpha=0.05):
    """TOST 等效检验"""
    diff = x - y
    # Test H0: diff <= lower
    t1, p1 = stats.ttest_1samp(diff - lower, 0, alternative='greater')
    # Test H0: diff >= upper
    t2, p2 = stats.ttest_1samp(diff - upper, 0, alternative='less')
    return max(p1, p2)

def main(data_dir):
    sessions = sorted(Path(data_dir).glob("session-*-env.json"))
    
    noir_data = []
    gpui_data = []
    
    for session_env in sessions:
        session_id = session_env.stem.replace("-env", "")
        
        # 读取数据
        noir_file = session_env.parent / f"{session_id}-noir.jsonl"
        gpui_file = session_env.parent / f"{session_id}-gpui.jsonl"
        
        noir_batches = [json.loads(line)['ns_per_handler'] 
                       for line in noir_file.read_text().splitlines()]
        gpui_batches = [json.loads(line)['ns_per_handler']
                       for line in gpui_file.read_text().splitlines()]
        
        noir_data.append(np.array(noir_batches))
        gpui_data.append(np.array(gpui_batches))
    
    # 配对分析
    noir_all = np.concatenate(noir_data)
    gpui_all = np.concatenate(gpui_data)
    
    # Hodges-Lehmann 估计
    hl_diff = hodges_lehmann_estimator(noir_all, gpui_all)
    ci = bootstrap_ci(noir_all, gpui_all, hodges_lehmann_estimator)
    
    # 相对改善
    median_noir = np.median(noir_all)
    median_gpui = np.median(gpui_all)
    relative_improvement = (median_gpui - median_noir) / median_gpui * 100
    
    print(f"Noir 中位数: {median_noir/1e6:.2f} ms")
    print(f"GPUI 中位数: {median_gpui/1e6:.2f} ms")
    print(f"Hodges-Lehmann 差: {hl_diff/1e6:.2f} ms [95% CI: {ci[0]/1e6:.2f}–{ci[1]/1e6:.2f}]")
    print(f"相对改善: {relative_improvement:.1f}%")
    
    # Session 方向一致性
    session_favors_noir = sum(
        np.median(noir) < np.median(gpui) 
        for noir, gpui in zip(noir_data, gpui_data)
    )
    print(f"Session 方向一致性: {session_favors_noir}/{len(sessions)} favor Noir")
    
    # 配对符号检验
    sign_test = stats.wilcoxon(noir_all - gpui_all, alternative='less')
    print(f"Wilcoxon p-value: {sign_test.pvalue:.4f}")
    
    # 结论
    if ci[1] < 0 and session_favors_noir >= 4 and abs(relative_improvement) >= 10:
        print("\n✓ 显著且实际有意义")
    elif abs(relative_improvement) < 5 and ci[0] > -0.05*median_gpui and ci[1] < 0.05*median_gpui:
        print("\n≈ 统计等效")
    else:
        print("\n? 证据不足")

if __name__ == "__main__":
    import sys
    main(sys.argv[1])
```

---

## 总结

**当前 15-sample 数据的正确评估**:

1. **Click handler**: 值得正式确认的强候选（但需 5×200 protocol）
2. **Scroll**: 应以等效检验为目标，不预设 Noir 获胜
3. **GPU timestamp**: 单次运行，不足以下结论

**关键原则**:

- ✅ 25-click batch = 1 个样本（不是 25 个）
- ✅ 预热、独立 session、随机化是必需的
- ✅ 配对分析、Hodges-Lehmann、TOST
- ✅ 三类结论标签：显著、等效、不足
- ✅ GPU 与 X11 endpoint 分离测量

**不要**:

- ❌ 将相关观测当独立样本
- ❌ 忽略预热和 session 间变异
- ❌ 假设"没有显著性 = 等效"
- ❌ 混合不同测量边界的数据
