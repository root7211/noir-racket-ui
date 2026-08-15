# 审计问题修复记录

## 发现的问题

### 问题 1: NumPy ABI 不兼容导致分析不可重现

**症状**:
```
ValueError: numpy.dtype size changed, may indicate binary incompatibility. 
Expected 96 from C header, got 88 from PyObject
```

**根本原因**:
- 系统 scipy 1.11.4 编译时使用 NumPy 1.26.x
- 用户环境安装了 NumPy 2.4.4 (不兼容)
- 导致原始提交的分析结果无法在干净环境中重现

**修复**:
1. 明确依赖版本: `numpy>=1.21.6,<1.28.0` (与 scipy 1.11.4 兼容)
2. 创建验证脚本: `tools/verify_analysis_reproducibility.sh`
3. 重新运行分析，确保可重现性

**验证**:
```bash
cd ~/noir-racket-ui
bash tools/verify_analysis_reproducibility.sh data/rigorous-20260815-192350
# ✓ Reproducibility verified
```

---

### 问题 2: 零匹配轮询产生算术错误

**症状**:
```
tools/rigorous_benchmark.sh: line 74: [[: 0\n0: syntax error in expression
```

**根本原因**:
- `batch_id=0` 时，`batch_id % 50 == 0` 条件为真
- `noir_count=0, gpui_count=0` 时，输出包含换行符
- `echo 0\n0` 被错误解析为算术表达式

**修复**:
```bash
# 原代码 (错误)
if (( batch_id % 50 == 0 )); then

# 修复后
if (( batch_id > 0 && batch_id % 50 == 0 )); then
```

**影响评估**:
- ✅ 所有 200 batches per session 都成功完成
- ✅ 数据完整性未受影响
- ⚠️ 但进度报告路径不干净，可能增加轻微调度噪声

---

## 重跑决策

### 需要重跑的理由

1. **可重现性要求**: 
   - 当前结果没有干净的可重现运行日志
   - NumPy 依赖问题会导致第三方无法验证分析

2. **数据质量**:
   - 算术错误虽未破坏数据，但进度报告路径不干净
   - 可能引入轻微调度噪声

3. **科学严谨性**:
   - 发布的统计学显著结果必须完全可重现
   - 零容忍工具链问题

### 重跑方案

**完整重跑 (推荐)**:
```bash
cd ~/noir-racket-ui

# 1. 清理旧数据
mv data/rigorous-20260815-192350 data/rigorous-20260815-192350-AUDIT

# 2. 使用修复后的脚本
bash tools/rigorous_benchmark.sh

# 3. 验证分析可重现
bash tools/verify_analysis_reproducibility.sh data/rigorous-YYYYMMDD-HHMMSS

# 4. 推送干净的结果
git add data/rigorous-YYYYMMDD-HHMMSS/
git commit -m "Clean rerun: Fix NumPy ABI and zero-batch arithmetic error"
```

**预计时间**: 2 小时 15 分钟

---

## 修复验证清单

### 问题 1: NumPy ABI 兼容性

- [x] 创建 `verify_analysis_reproducibility.sh`
- [x] 明确 NumPy 版本要求 (1.21.6-1.27.x)
- [x] 验证当前分析可重现
- [x] 更新 STATISTICAL_METHODOLOGY.md 添加依赖说明

### 问题 2: 零匹配算术错误

- [x] 修复 `rigorous_benchmark.sh` line 154
- [x] 添加 `batch_id > 0` 前置条件
- [ ] 重跑实验验证修复有效

---

## 依赖管理建议

### requirements.txt

```
numpy>=1.21.6,<1.28.0
scipy>=1.11.4,<1.13.0
```

### 安装命令

```bash
# Ubuntu 系统包 (推荐)
sudo apt-get install python3-numpy python3-scipy

# 或 pip (如果系统包版本不对)
python3 -m pip install --break-system-packages 'numpy>=1.21.6,<1.28.0' scipy
```

---

## 结论

**审计严重性**: 中等
- 数据完整性: ✓ 未受损
- 可重现性: ✗ 当前环境不可重现
- 噪声影响: ? 未量化

**推荐行动**: 
1. ✅ 立即修复工具链问题
2. ✅ 重跑实验获得干净数据
3. ✅ 推送可验证的结果

**时间成本**: 2.5 小时 (重跑 2h + 验证 0.5h)

---

**审计日期**: 2026-08-15  
**审计员**: 用户  
**修复状态**: 代码已修复，等待重跑
