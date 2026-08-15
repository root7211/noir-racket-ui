# Noir：Profile-guided Cost Calibration

## 结论

Noir 的三档 Render Strategy 已由纯硬编码权重升级为**冻结 profile 驱动的编译期成本选择**。校准器使用当前 wgpu adapter 的 timestamp query 采样实际 GPU command 工作和 CPU encode/submit 时间，写出版本化 JSON profile；Racket 宏仅在展开期读取该 profile，并将 `profile_id`、候选成本和策略结果固化到 Scene JSON。wgpu runtime 不查询 profile，不在运行时重新拟合或自适应。

> **测量发生在开发/校准阶段；选择发生在编译阶段；发布 runtime 只执行冻结的 Render Schedule。**

## 校准器

新增 `wgpu-verify/src/bin/calibrate.rs`。它首先协商 `TIMESTAMP_QUERY` 与 `TIMESTAMP_QUERY_INSIDE_ENCODERS`；支持时，以 64 次真实 `CommandEncoder` buffer-clear 工作负载采样 GPU timestamp，并同时记录 CPU encode/submit wall-clock。若 adapter 不支持 timestamp，则明确写出 `cpu-submit-fallback` profile，而非伪造 GPU 数据。

本次环境的实际 profile 为：

| 字段 | 实测值 |
|---|---:|
| Adapter | `llvmpipe (LLVM 20.1.2, 256 bits)` |
| Backend | Vulkan / CPU adapter |
| Timestamp query | 支持 |
| Timestamp period | 1.0 ns |
| 采样 repetitions | 64 |
| CPU encode/submit | 16,420.02 ns/命令 |
| GPU timestamp | 1,702.17 ns/命令 |
| Profile ID | `noir-vulkan-gpu-timestamp-v1` |

冻结文件位于 `profiles/wgpu-calibrated.json`。它保存来源 adapter、后端、采样模式和全部系数，因而 profile 是可审计的构建输入，而不是隐式环境状态。

## 编译期消费契约

当设置 `NOIR_COST_PROFILE=/path/to/profile.json` 时，`#lang noir/ui` 的 Racket 宏在展开期读取 profile：

```text
candidate_cost = draw_range_ns × range_count
               + clip_switch_ns × range_count
               + covered_pixel_ns × covered_area
```

对 `full-tile-redraw`，覆盖面积再乘 `full_tile_multiplier`。宏把选择结果写入每个 Render Tile：

| Scene JSON 字段 | 目的 |
|---|---|
| `profile_id` | 将 Render Schedule 关联到冻结 profile。 |
| `candidate_costs` | 保存 fragment / complete-lower-range / full-tile 的完整比较。 |
| `selected_strategy` | runtime 必须执行的路径。 |
| `fallback_reason` | 说明是预算、成本最小值还是整体覆盖率导致的决策。 |

## 实际 profile 下的策略验证

三 tooltip 的 progress tile 仍因 fragment 数超过安全预算而使 fragment 候选成本固定为 `1e30`。使用 Vulkan timestamp profile 后，compiler 对该 tile 选择 `full-tile-redraw`；两个轻量 button tile 选择 `fragment`。这说明 profile 改变权重来源，但不会绕过 Fragment Budget 的正确性上界。

| 验证项 | 结果 |
|---|---:|
| Render Schedule profile ID | `noir-vulkan-gpu-timestamp-v1` |
| 局部 tiles / 覆盖率 | 3 / 12.7396% |
| 局部提交 instances | 10 |
| 全量参考提交 | 45 |
| Host layout solver calls | 0 |
| 共享 pipeline | 1 |
| wgpu runtime 重拟合 | 0 次 |
| 局部输出 vs 全 Scene oracle | 完全一致 |

![Profiled local rendering](out/noir-profiled-concurrent-040ms.png)

## 运行方式

```bash
cd wgpu-verify
XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime WGPU_BACKEND=vulkan \
  cargo run --release --bin calibrate -- ../profiles/wgpu-calibrated.json

cd ..
PLTCOLLECTS="$PWD:/usr/share/racket/collects" \
NOIR_COST_PROFILE="$PWD/profiles/wgpu-calibrated.json" \
  racket tools/export-dashboard.rkt out/profiled.scene.json

cd wgpu-verify
XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime WGPU_BACKEND=vulkan \
  cargo run --release --bin noir-wgpu-verify -- ../out/profiled.scene.json out/noir-profiled
```

## 当前边界

当前校准 workload 是单一 command encoder/buffer-clear microbenchmark，目的是验证端到端数据链而非宣称它代表所有 GUI GPU 行为。下一步应扩展 profile 采样矩阵，分别测量实例化 quad、glyph atlas sampling、clip switch、alpha blend、query resolve 和不同 tile 覆盖面积；随后对每种 wgpu backend 和真实设备生成独立 profile。仍应保持原则不变：**profile 在构建时冻结，runtime 不在线学习。**
