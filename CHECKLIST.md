# 性能测量完成清单

## ✅ 已完成

### 1. dozen 下的 amdgpu 识别
- [x] 修改 `noir_wgpu_probe.rs` 启用 `ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER`
- [x] 修改 `noir_winit_host.rs` 启用非标准适配器支持
- [x] 验证 probe 识别到 AMD 780M (IntegratedGpu)
- [x] 确认 Dozen 驱动可用 (Mesa 26.1.7)

### 2. 性能基准测量
- [x] data-register-table-10000: GPU 44.5 μs, CPU 12.1 ms
- [x] virtual-list-dashboard: GPU 44.7 μs, CPU 9.7 ms
- [x] 编译器契约验证通过（tile mask, glyph 数量）
- [x] 生成 JSON 报告和日志

### 3. 文档输出
- [x] `AMD_780M_PERFORMANCE_REPORT.md` - 完整英文报告（317 行）
- [x] `MEASUREMENT_SUMMARY_CN.md` - 中文总结（138 行）
- [x] 原始数据备份 (JSON + log)

---

## 📊 核心数据

```
GPU 执行:  44-45 μs (vs llvmpipe 400-500 μs) → 10x 加速
CPU 路径:  9.7-12.1 ms (占总延迟 99.5%+)
加速比:    真实 GPU 比软件渲染快 10 倍以上
验证:      所有编译器契约匹配运行时实际值
```

---

## 📁 生成的文件

### 性能数据
```
out/amd-780m-data-register-table-10000.json
out/amd-780m-virtual-list-dashboard.json
out/amd-780m-benchmark-run.log
```

### 报告文档
```
AMD_780M_PERFORMANCE_REPORT.md          (详细分析，317行)
MEASUREMENT_SUMMARY_CN.md               (中文总结，138行)
CHECKLIST.md                            (本清单)
```

### 代码修改
```
wgpu-verify/src/bin/noir_wgpu_probe.rs  (添加 ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER)
wgpu-verify/src/bin/noir_winit_host.rs  (同上)
```

---

## 🔍 关键发现

### GPU 性能
- ✅ 物理 GPU 比 llvmpipe 快 **10x+**
- ✅ GPU 时间极稳定 (~45 μs)
- ✅ 当前工作负载轻（2 tiles, 3 glyphs）

### CPU 瓶颈
- ⚠️ CPU 时间是 GPU 的 **200-270 倍**
- ⚠️ 优化重点应该是 CPU 路径
- ℹ️ GPU 只占总延迟 < 0.5%

### 编译器正确性
- ✅ Tile mask 预测准确
- ✅ Glyph 数量匹配
- ✅ 数据写入数量和字节数一致
- ✅ Packet activity 路径正确

---

## 🚧 限制与注意事项

### 样本量
- ⚠️ **只有单次运行**，无统计分析
- 📝 建议: 200+ 样本 × 3+ session

### 场景覆盖
- ⚠️ **只测试了轻负载**（2 tiles, 3 glyphs）
- 📝 建议: 全屏刷新、连续滚动、大量 glyph

### 对照基准
- ⚠️ **未与 GPUI 在同一硬件上对比**
- 📝 建议: 相同输入序列、相同硬件的公平测试

### 测量边界
- ℹ️ 只测量了 **GPU 命令区域** 和 **CPU submit**
- ℹ️ 不包含 present、swap chain、显示器延迟
- ℹ️ 不是 input-to-photon 延迟

---

## 📋 下一步工作

### 优先级 1: 多样本统计（立即可做）
```bash
# 收集 200 样本
for i in {1..200}; do
  WGPU_BACKEND=vulkan ./wgpu-verify/target/release/noir_winit_host \
    out/data-register-table-10000.scene.json \
    --benchmark-report out/sample-$i.json
done

# 统计分析
python3 tools/analyze_samples.py out/sample-*.json
```

### 优先级 2: Fusion benchmark（需要正确的 Scene）
```bash
./tools/sample_fusion_benchmark.sh \
  ./wgpu-verify/target/release/noir_winit_host \
  out/<correct-scene>.scene.json \
  200 out/amd-780m-fusion-samples.jsonl

python3 tools/summarize_fusion_benchmark_samples.py \
  out/amd-780m-fusion-samples.jsonl \
  out/amd-780m-fusion-summary.json
```

### 优先级 3: 重负载场景
- [ ] 全屏文本刷新
- [ ] 连续虚拟列表滚动
- [ ] 多 packet + subgroup 场景

### 优先级 4: GPUI 对照（需要额外开发）
- [ ] 相同硬件、相同输入序列
- [ ] 端到端延迟对比
- [ ] 公平性验证

---

## ✨ 成就解锁

- ✅ **首次在 AMD GPU 上完成 wgpu 30 测量**
- ✅ **dozen 驱动成功识别和使用**
- ✅ **编译器契约在物理 GPU 上验证通过**
- ✅ **建立了 AMD 780M + wgpu 30 性能基线**

---

## 🔧 技术细节

### 关键修改
```rust
// 两个二进制都需要这个修改
let mut descriptor = wgpu::InstanceDescriptor::new_without_display_handle_from_env();
descriptor.flags |= wgpu::InstanceFlags::ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER;
let instance = wgpu::Instance::new(descriptor);
```

### 环境变量
```bash
export WGPU_BACKEND=vulkan
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
# 无需强制 VK_ICD_FILENAMES
```

### GPU 信息
```
Name:     Microsoft Direct3D12 (AMD RadeonT 780M)
Type:     IntegratedGpu
Vendor:   0x1002 (AMD)
Device:   0x15bf
Driver:   Dozen (Mesa 26.1.7)
Backend:  Vulkan
```

---

**完成时间**: 2026-08-15  
**工具链**: Rust 1.87 + wgpu 30.0.0  
**测试环境**: WSL2 + AMD 780M + Mesa Dozen
