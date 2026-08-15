# 统计学正确的性能测量实验计划

## 当前状态

### ✅ 已完成
1. **探索性测试** (15 samples)
   - 识别了性能差异的方向
   - Click handler: Noir 可能更快
   - Scroll: 可能等效
   - 状态: 探索性观察，非正式结论

2. **统计方法文档** (STATISTICAL_METHODOLOGY.md)
   - 正确的实验设计
   - 配对分析方法
   - 三类结论标签体系

3. **实验脚本**
   - `tools/rigorous_benchmark.sh`: 主测试脚本
   - `tools/analyze_rigorous_benchmark.py`: 统计分析
   - `tools/quick_validation_test.sh`: 快速验证

---

## 实验协议

### Phase 1: 快速验证 (进行中)

**目的**: 验证脚本正确性和数据质量

**参数**:
- Sessions: 2
- Warmup: 10 batches per framework
- Measurement: 20 batches per framework
- 预计时间: 10-15 分钟

**成功标准**:
- 所有 batches 成功完成
- 数据格式正确
- 分析脚本运行无错
- 初步结果方向一致

### Phase 2: 完整正式测试 (待执行)

**目的**: 建立统计学显著的结论

**参数**:
- Sessions: **5**
- Warmup: **50** batches per framework
- Measurement: **200** batches per framework per session
- 总观测数: **1,000** per framework
- 预计时间: **2-3 小时**

**随机化**:
- 每个 session 内随机化顺序
- 区组化设计 (每个 block 包含 1 noir + 1 gpui)

**环境控制**:
- 记录 CPU governor
- Session 间 60 秒冷却
- 独立的 Xvfb 实例

### Phase 3: GPU Timestamp 独立采集 (待执行)

**目的**: 分离 GPU 执行时间和 CPU 路径开销

**参数**:
- Sessions: 5
- Warmup: 50 runs per scene
- Measurement: 200 runs per scene per session
- Scenes: 
  - data-register-table-10000
  - virtual-list-dashboard
  - composite-worklist-dashboard (如果可用)

**测量指标**:
- `gpu_elapsed_ns`: GPU 命令执行时间
- `cpu_submit_ns`: CPU event-to-submit 时间
- 必须分开分析，不能混合

---

## 分析计划

### Click Handler Endpoint

**假设**: Noir < GPUI (单侧检验)

**分析方法**:
1. Hodges-Lehmann 估计 (配对差值中位数)
2. 95% Bootstrap 置信区间
3. Wilcoxon 符号秩检验
4. Session 方向一致性检查

**判定标准**:
- 95% CI 不跨零
- ≥4/5 sessions 方向一致
- 相对改善 ≥10%
- → 结论: ✓ 显著且实际有意义

### Scroll Endpoint

**假设**: |Noir - GPUI| < 5% (等效性)

**分析方法**:
1. TOST (Two One-Sided Tests)
2. 等效区间: ±5% 相对差异
3. 按 session 独立报告 P95/P99

**判定标准**:
- 95% CI 完全落在 [-5%, +5%] 内
- TOST p < 0.05
- → 结论: ≈ 统计等效

**尾延迟诊断**:
- 按 session 报告 P95/P99
- 识别异常值 (例如 GPUI 的 36 ms 峰值)
- 不与中位数混合分析

### GPU Timestamp

**分析方法**:
1. 独立于 X11 endpoint
2. 按 scene 分别分析
3. 报告中位数、P95、P99
4. 方差分析 (跨 session)

**不要做**:
- ❌ 与 X11 延迟混合
- ❌ 与 CPU submit 时间混合
- ❌ 称为"总延迟"

---

## 预期结果与决策树

### 场景 A: Click Handler 显著

**条件**:
- CI 不跨零
- Session 一致
- 改善 ≥10%

**结论**: ✓ 显著且实际有意义

**发布**:
- 主要发现
- 强调编译期优化的价值
- 建议: 适合低延迟交互场景

### 场景 B: Scroll 等效

**条件**:
- 95% CI 在 ±5% 内
- TOST 显著

**结论**: ≈ 统计等效

**发布**:
- 补充发现
- 强调: 滚动性能相当
- 关注: GPUI 尾延迟需诊断

### 场景 C: 证据不足

**条件**:
- CI 跨零或跨等效界限
- Session 不一致

**结论**: ? 证据不足

**行动**:
- 增加样本量
- 检查实验协议
- 可能需要更大的效应量

---

## 发布标准

### 最低标准 (可发布)

- [ ] 3 sessions × 50 batches (150 独立观测)
- [ ] 配对分析 + Bootstrap CI
- [ ] 报告三类结论标签
- [ ] 原始数据公开

### 推荐标准 (高质量)

- [ ] **5 sessions × 200 batches (1,000 独立观测)**
- [ ] 随机化 + 区组化
- [ ] Hodges-Lehmann + TOST
- [ ] 按 session 报告 P95/P99
- [ ] GPU timestamp 独立采集
- [ ] 完整环境元数据

### 当前进度

```
Phase 1: Quick Validation     [████████░░] 80% (进行中)
Phase 2: Full Rigorous Test   [░░░░░░░░░░]  0% (待执行)
Phase 3: GPU Timestamp        [░░░░░░░░░░]  0% (待执行)
```

---

## 时间估算

| 阶段 | 预计时间 | 状态 |
|------|---------|------|
| Phase 1 验证 | 10-15 分钟 | 进行中 |
| Phase 2 完整测试 | 2-3 小时 | 待执行 |
| Phase 3 GPU 采集 | 1-2 小时 | 待执行 |
| 数据分析 | 30 分钟 | 待执行 |
| 报告撰写 | 1 小时 | 待执行 |
| **总计** | **5-7 小时** | - |

---

## 检查清单

### 实验执行前

- [x] 脚本已创建并可执行
- [x] 统计方法文档完成
- [ ] 快速验证测试通过
- [ ] Xvfb 稳定运行
- [ ] 足够的磁盘空间 (原始数据 ~100 MB)

### 实验执行中

- [ ] 监控进度日志
- [ ] 检查每个 session 的完成率
- [ ] 记录任何异常或失败
- [ ] 保存环境快照

### 数据分析

- [ ] 所有 session 数据完整
- [ ] Bootstrap CI 收敛
- [ ] Session 方向一致性
- [ ] P 值合理

### 发布前

- [ ] 原始数据已备份
- [ ] 分析脚本可重现
- [ ] 报告包含所有三类结论
- [ ] 限制和假设明确说明
- [ ] 代码和数据推送到 GitHub

---

## 下一步行动

### 立即 (Phase 1 完成后)

1. 检查快速验证结果
2. 验证数据质量和脚本正确性
3. 如果成功，启动 Phase 2 完整测试

### Phase 2 启动条件

- ✓ Phase 1 所有 batches 成功
- ✓ 数据格式正确
- ✓ 分析脚本无错
- ✓ 结果方向合理

### Phase 2 执行

```bash
# 在后台运行完整测试
cd ~/noir-racket-ui
nohup bash tools/rigorous_benchmark.sh > data/rigorous-full.log 2>&1 &

# 监控进度
tail -f data/rigorous-full.log

# 或查看最新的 output 目录
ls -lt data/rigorous-* | head -1
tail -f data/rigorous-YYYYMMDD-HHMMSS/progress.log
```

### Phase 3 执行

```bash
# GPU timestamp 独立采集脚本 (待创建)
bash tools/gpu_timestamp_protocol.sh
```

---

## 风险与缓解

### 风险 1: 测试时间过长

**影响**: 2-3 小时可能受环境变化影响

**缓解**:
- Session 间冷却期
- 记录温度/频率变化
- 如果中断，可从上次 session 继续

### 风险 2: Xvfb 不稳定

**影响**: 窗口查找失败，batch 失败

**缓解**:
- 每个 session 重启 Xvfb
- 增加等待时间
- 记录失败的 batch

### 风险 3: 结果不显著

**影响**: 需要更多样本或更大效应

**缓解**:
- 已有探索性数据作指导
- 可以扩展到 10 sessions
- 考虑其他 workload

### 风险 4: Session 间变异大

**影响**: CI 宽，难以下结论

**缓解**:
- 区组化设计减少变异
- 按 session 单独分析
- 报告 session-level 效应

---

**文档版本**: v1.0  
**最后更新**: 2026-08-15  
**状态**: Phase 1 进行中
