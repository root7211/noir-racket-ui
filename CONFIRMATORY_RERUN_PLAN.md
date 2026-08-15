# 确认性重跑计划

## 当前状态评估

**结论**: "强确认性候选"，而非"已证实"

**问题**:
1. ✗ 采集轮询错误（零匹配计数产生 `0\n0`）
2. ✗ SciPy 环境不可重现
3. ✗ 缺少审计元数据
4. ✗ 未经独立环境验证

---

## 优先级 1-6 工作清单

### 1. 修复零匹配计数轮询

**当前问题**:
```bash
count=$(grep -c "$expected" "$log" 2>/dev/null || echo 0)
# 可能产生: 0\n0 (多行输出)
```

**修复**:
```bash
# 方案 A: 明确单行输出
count=$(grep -c "$expected" "$log" 2>/dev/null || printf "0")

# 方案 B: 显式失败处理
if ! count=$(grep -c "$expected" "$log" 2>/dev/null); then
    count=0
    echo "WARNING: No matches found in $log" | tee -a "$OUTPUT_DIR/failures.log"
fi

# 方案 C (推荐): Incomplete batch 写入失败记录
if [[ "$count" -ne "$clicks" ]]; then
    echo "{\"session\":\"$SESSION_ID\",\"framework\":\"$framework\",\"batch\":$batch_id,\"expected\":$clicks,\"actual\":$count,\"status\":\"incomplete\"}" \
      >> "$OUTPUT_DIR/incomplete-batches.jsonl"
    return 1  # 不静默继续
fi
```

**实现**: 采用方案 C

---

### 2. 固定分析环境

**requirements.txt**:
```
# Pinned for reproducibility with scipy 1.11.4
numpy==1.26.4
scipy==1.11.4

# Optional: faster bootstrap
numba>=0.58.0
```

**验证 CI**:
```bash
# .github/workflows/verify-analysis.yml
- name: Install dependencies
  run: python3 -m pip install -r requirements.txt

- name: Run analysis
  run: python3 tools/analyze_rigorous_benchmark.py data/rigorous-*/

- name: Verify results.json exists
  run: test -f data/rigorous-*/analysis-results.json
```

---

### 3. 记录可审计元数据

**扩展 session-XX-env.json**:
```json
{
  "session_id": "session-01",
  "session_number": 1,
  "start_time": "2026-08-15T21:54:16+08:00",
  "adapter": {
    "name": "Microsoft Direct3D12 (AMD RadeonT 780M)",
    "vendor": "0x1002",
    "device": "0x15bf",
    "driver": "Dozen",
    "driver_info": "Mesa 26.1.7 - kisak-mesa PPA"
  },
  "system": {
    "os": "Linux 6.6.87.2-microsoft-standard-WSL2",
    "cpu_governor": "performance",
    "power_state": "AC",
    "temperature_c": null
  },
  "build": {
    "git_commit": "ee9da2e",
    "noir_binary_sha256": "...",
    "gpui_binary_sha256": "..."
  },
  "randomization": {
    "seed": 42,
    "block_order": [...]
  }
}
```

**采集脚本**:
```bash
# 在每个 session 开始时
ADAPTER_INFO=$(WGPU_BACKEND=vulkan ./wgpu-verify/target/release/noir_wgpu_probe 2>&1 | grep 'adapter\[0\]')
GIT_COMMIT=$(git rev-parse --short HEAD)
NOIR_SHA256=$(sha256sum wgpu-verify/target/release/noir_winit_host | awk '{print $1}')
```

---

### 4. 重跑确认实验

**协议**:
- 保持: 5 sessions × 50 warmup × 200 measurement
- **新增**: 跨独立环境验证
  - Run A: Xvfb :93 (当前)
  - Run B: Xvfb :94 (独立实例)
  - 或: 跨日执行（今天 + 明天）

**完成标准**:
- 所有 batches 成功，无 incomplete 记录
- 分析脚本在 CI 中可重现
- 元数据完整记录

---

### 5. 分层主分析

**当前问题**:
- Batch-level Wilcoxon 将 5×200 个高度相关的 batches 当作独立样本
- 正确做法: Session 是独立单位

**修复**:
```python
# 主分析: Session-level bootstrap
session_medians_noir = [np.median(s) for s in noir_sessions]
session_medians_gpui = [np.median(s) for s in gpui_sessions]

def bootstrap_session_diff(noir_sessions, gpui_sessions, n_boot=10000):
    n_sessions = len(noir_sessions)
    diffs = []
    for _ in range(n_boot):
        idx = np.random.choice(n_sessions, n_sessions, replace=True)
        noir_resample = [noir_sessions[i] for i in idx]
        gpui_resample = [gpui_sessions[i] for i in idx]
        
        noir_grand_median = np.median(np.concatenate(noir_resample))
        gpui_grand_median = np.median(np.concatenate(gpui_resample))
        diffs.append(noir_grand_median - gpui_grand_median)
    return np.percentile(diffs, [2.5, 97.5])

# 主 p 值: Wilcoxon on session medians (n=5)
wilcoxon_session = stats.wilcoxon(session_medians_noir, session_medians_gpui)

# 补充: Batch-level (仅作为敏感性分析)
wilcoxon_batch = stats.wilcoxon(noir_all, gpui_all)
```

---

### 6. Scroll 等效实验

**预注册**:
- H0: |Noir - GPUI| ≥ 5% (非等效)
- H1: |Noir - GPUI| < 5% (等效)
- TOST α = 0.05

**分析计划**:
1. 中位数等效检验 (TOST)
2. 按 session 报告 P95/P99
3. 尾部诊断: 识别 >2×median 的异常值

**不做**:
- ❌ 预设 Noir 获胜
- ❌ 将等效失败解释为"没有差异"
- ❌ 混合中位数和尾延迟

---

## 实施计划

### Phase 1: 工具链修复 (30 分钟)

1. 修复 `rigorous_benchmark.sh`:
   - 零匹配计数 → `printf "0"`
   - Incomplete batch → 写入 `incomplete-batches.jsonl`
   - 添加 `set -o pipefail`

2. 创建 `requirements.txt`:
   ```
   numpy==1.26.4
   scipy==1.11.4
   ```

3. 扩展元数据采集:
   - Adapter info
   - Git commit + binary SHA256
   - CPU governor, 电源状态

4. 验证修复:
   ```bash
   bash -n tools/rigorous_benchmark.sh
   python3 -m pip install -r requirements.txt
   python3 tools/analyze_rigorous_benchmark.py --dry-run
   ```

### Phase 2: 确认性重跑 (2.5 小时)

1. 清理环境:
   ```bash
   mv data/rigorous-2026* data/archive/
   ```

2. 执行重跑:
   ```bash
   bash tools/rigorous_benchmark.sh
   ```

3. 验证无错误:
   ```bash
   # 检查没有 incomplete batches
   [ ! -f data/rigorous-*/incomplete-batches.jsonl ] || {
       echo "ERROR: Found incomplete batches"
       cat data/rigorous-*/incomplete-batches.jsonl
       exit 1
   }
   
   # 检查所有 session 完成
   [ $(find data/rigorous-* -name "session-*.jsonl" | wc -l) -eq 10 ] || {
       echo "ERROR: Expected 10 session files (5 × 2 frameworks)"
       exit 1
   }
   ```

4. 运行分析:
   ```bash
   python3 tools/analyze_rigorous_benchmark.py data/rigorous-*/
   bash tools/verify_analysis_reproducibility.sh data/rigorous-*/
   ```

### Phase 3: 分层分析实现 (1 小时)

1. 更新 `analyze_rigorous_benchmark.py`:
   - 实现 session-level bootstrap
   - Session median Wilcoxon 作为主检验
   - Batch-level 降级为补充

2. 添加敏感性分析:
   - 单个 session 的影响
   - 不同 block 顺序的稳健性

### Phase 4: 独立验证 (可选, 2.5 小时)

跨日或跨 Xvfb 实例重跑一次

---

## 成功标准

### 技术标准

- [ ] 零轮询错误修复验证通过
- [ ] 分析在 CI 中可重现
- [ ] 完整审计元数据记录
- [ ] 无 incomplete batches
- [ ] Session-level 主分析实现

### 统计标准

- [ ] Session-level CI 不跨零
- [ ] 5/5 sessions 方向一致
- [ ] 相对改善 ≥ 10%
- [ ] 分层 bootstrap p < 0.05

### 报告标准

升级结论为:

> 在 AMD 780M / WSL2 Dozen / Xvfb 的固定点击 endpoint 中，Noir 相对 GPUI 具有**统计显著且实际有意义**的优势（session-level 中位数差 ~600 μs，95% CI [-650, -550] μs，5/5 sessions 一致）。

**限定条件**:
- 环境: WSL2 + Dozen + Xvfb
- Endpoint: X11 input → handler (不含 GPU present)
- 场景: 固定虚拟列表点击

**不声称**:
- ❌ 原生 Linux 上的优势
- ❌ 真实显示器的 input-to-photon 延迟
- ❌ Scroll 场景的优势（需独立实验）

---

## 时间估算

| 阶段 | 时间 |
|------|------|
| Phase 1: 工具链修复 | 30 分钟 |
| Phase 2: 确认性重跑 | 2.5 小时 |
| Phase 3: 分层分析 | 1 小时 |
| Phase 4: 独立验证 (可选) | 2.5 小时 |
| **最低总计** | **4 小时** |
| **完整验证** | **6.5 小时** |

---

**文档版本**: v1.0  
**创建时间**: 2026-08-15 22:15  
**状态**: Phase 1 待执行
