# AMD 780M 性能测量总结

## ✅ 完成情况

**dozen 下的 amdgpu 识别**: ✓ 成功  
**性能基准测量**: ✓ 完成（初步数据）  
**wgpu 30 迁移验证**: ✓ 通过

---

## 核心数据

### GPU 识别
```
名称: Microsoft Direct3D12 (AMD RadeonT 780M)
类型: IntegratedGpu
供应商: 0x1002 (AMD)
设备: 0x15bf
驱动: Mesa Dozen 26.1.7
后端: Vulkan
```

### 性能对比

| 指标 | AMD 780M | llvmpipe | 加速比 |
|------|----------|----------|--------|
| GPU 执行时间 | **44-45 μs** | 400-500 μs | **10x+** |
| CPU submit | 9.7-12.1 ms | 0.17-14.6 ms | 波动较大 |
| 总延迟 | ~10-12 ms | ~14-15 ms | ~1.2-1.5x |

### 测试场景

1. **data-register-table-10000**: 10K 行虚拟列表，coalesced batch
   - GPU: 44.5 μs
   - CPU: 12.1 ms
   - Tiles: 2, Glyphs: 3

2. **virtual-list-dashboard**: 虚拟列表交互
   - GPU: 44.7 μs
   - CPU: 9.7 ms
   - Tiles: 2, Glyphs: 3

---

## 关键发现

### 1. GPU 性能极佳
- 真实 GPU 比软件渲染快 **10 倍以上**
- 两个场景的 GPU 时间几乎相同（~45 μs），说明工作负载轻且稳定

### 2. CPU 成为瓶颈
- CPU 时间（9.7-12.1 ms）是 GPU 时间（~45 μs）的 **200-270 倍**
- GPU 只占总延迟的 **< 0.5%**
- 优化重点应放在 CPU 路径：事件分发、状态更新、batch 合并

### 3. 编译器正确性验证通过
- ✓ Tile mask 匹配（编译期预测 == 运行期实际）
- ✓ Glyph 数量匹配
- ✓ 数据写入数量和字节数匹配
- ✓ Packet activity 预测准确

### 4. wgpu 30 迁移成功
- 需要 `ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER` 标志识别 Dozen
- Timestamp query 支持正常（10 ns 周期）
- 所有 API 迁移（texture upload, surface acquire, present）均正常工作

---

## 技术要点

### 代码修改

两个二进制文件需要启用非标准适配器：

**noir_wgpu_probe.rs**:
```rust
let mut descriptor = wgpu::InstanceDescriptor::new_without_display_handle_from_env();
descriptor.flags |= wgpu::InstanceFlags::ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER;
let instance = wgpu::Instance::new(descriptor);
```

**noir_winit_host.rs**: 同样修改（已完成）

### 环境配置
```bash
export WGPU_BACKEND=vulkan
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
# 不需要强制设置 VK_ICD_FILENAMES
```

---

## 限制与后续工作

### 当前限制

1. **样本量不足**: 只有单次运行，无统计分析
2. **场景有限**: 只测试了轻负载场景（2 tiles, 3 glyphs）
3. **缺少对照**: 未与 GPUI 在同一硬件上对比
4. **测量边界**: 只有 GPU 命令区域和 CPU submit，不含 present 延迟

### 下一步工作

**优先级 1（立即可做）**:
- [ ] 收集 200+ 样本进行统计分析
- [ ] 测试重负载场景（全屏刷新、连续滚动）
- [ ] 运行 Fusion benchmark（验证 coalescing 收益）

**优先级 2（需要 Racket）**:
- [ ] 重新生成包含 3 个标准测试用例的 Scene
- [ ] 通过 `check-benchmark-report.js` 验证

**优先级 3（需要额外开发）**:
- [ ] GPUI 对照基准（相同硬件、相同输入）
- [ ] Input-to-photon 延迟测量（物理显示器）
- [ ] 多 GPU 对比（AMD vs NVIDIA vs Intel）

---

## 文件清单

### 代码修改
- `wgpu-verify/src/bin/noir_wgpu_probe.rs`: 启用非标准适配器
- `wgpu-verify/src/bin/noir_winit_host.rs`: 启用非标准适配器

### 性能数据
- `out/amd-780m-data-register-table-10000.json`: 10K 行列表基准
- `out/amd-780m-virtual-list-dashboard.json`: 虚拟列表交互基准
- `out/amd-780m-benchmark-run.log`: 详细运行日志

### 报告文档
- `AMD_780M_PERFORMANCE_REPORT.md`: 完整性能分析报告（英文）
- `MEASUREMENT_SUMMARY_CN.md`: 本总结文档（中文）
- `out/wsl-wgpu30-diagnostics.txt`: Vulkan 环境诊断（由工具生成）

---

## 结论

✅ **dozen 成功识别 AMD 780M**  
✅ **wgpu 30 迁移在真实 GPU 上验证通过**  
✅ **GPU 性能比 llvmpipe 快 10 倍以上**  
✅ **编译器契约在物理 GPU 上全部匹配**

🎯 **下一步重点**: 收集多样本统计数据，测试重负载场景，与 GPUI 对照。

---

**测量时间**: 2026-08-15  
**工具链**: Rust 1.87 + wgpu 30.0.0  
**环境**: WSL2 + AMD 780M + Mesa Dozen 26.1.7
