# Noir：Calibration Matrix 与多设备 Profile Selection

## 结论

Noir 已从单一 `clear-buffer` 时间戳校准扩展为 **Calibration Matrix**。校准器以同一 wgpu adapter 对六类固定 command workload 采样 CPU submission 与 GPU timestamp，并把 profile 写入可版本化 registry。Racket 宏通过 `NOIR_COST_PROFILE` 与 `NOIR_PROFILE_ID` 在**展开期**精确选择 profile；若 registry 不存在匹配项，则自动选择 `noir-static-cost-v1`，而不是猜测设备能力。

> **设备匹配、策略权重和回退都发生在构建期；runtime 只执行附带 profile ID 的固定 Render Schedule。**

## Calibration Matrix

新增 `wgpu-verify/src/bin/calibrate_matrix.rs`。每个 sample 使用 64 次重复测量，优先请求 `TIMESTAMP_QUERY` 与 `TIMESTAMP_QUERY_INSIDE_ENCODERS`，不支持时显式记录 `cpu-submit-fallback-matrix`。当前 llvmpipe Vulkan adapter 支持真实 GPU timestamp query。

| Matrix workload | 代表的 Noir 工作 | GPU timestamp / 命令 |
|---|---|---:|
| `quad-range-submit` | instance range 提交基础开销 | 4,325.80 ns |
| `glyph-atlas-upload-proxy` | text-run / atlas 相关 command proxy | 531.56 ns |
| `clip-switch-proxy` | 多 scissor / clip state proxy | 323.40 ns |
| `tile-small-proxy` | 小 tile 覆盖工作 | 417.67 ns |
| `tile-large-proxy` | 大 tile 覆盖工作 | 2,971.55 ns |
| `query-resolve` | timestamp query resolve/readback proxy | 1,026.53 ns |

这些 workload 是当前无窗口离屏验证器的 command-level 校准矩阵，不把它们误称为完整桌面 GUI 基准。它们的作用是为 compiler 提供一个可重复、可扩展且来自真实 adapter 的成本来源。

## Registry 与匹配规则

生成文件 `profiles/registry.json`：

```text
registry_version = 1
profiles[] = { profile_id, matcher, timestamp_supported,
               calibration_mode, samples, coefficients }
```

每个 `matcher` 至少包含 backend、adapter 和目标分辨率。当前 profile ID 是 `noir-vulkan-gpu-matrix-v1`，目标为 `Vulkan + llvmpipe + 640×360`。

| 构建输入 | 宏的选择行为 | Render Schedule `profile_id` |
|---|---|---|
| `NOIR_COST_PROFILE=registry.json`，且 `NOIR_PROFILE_ID=noir-vulkan-gpu-matrix-v1` | 精确命中矩阵 profile。 | `noir-vulkan-gpu-matrix-v1` |
| 同一 registry，`NOIR_PROFILE_ID` 不存在 | 严格回退，不选择“最接近” profile。 | `noir-static-cost-v1` |
| 直接 profile JSON，无指定冲突 ID | 维持向后兼容，直接读取 profile。 | profile 自身 ID |
| 未设置 profile 路径 | 使用内建静态 profile。 | `noir-static-cost-v1` |

精确 ID 而非模糊匹配是刻意的：它避免不同 driver、GPU 或分辨率的历史数据在没有审计的条件下影响渲染策略。

## 编译期成本消费

宏使用 profile 中的下列冻结系数：

```text
cost = draw_range_ns × range_count
     + clip_switch_ns × range_count
     + covered_pixel_ns × covered_area
```

`full_tile_multiplier` 只应用于 `full-tile-redraw` 候选。Scene JSON 继续导出 `candidate_costs`、`selected_strategy`、`fallback_reason`，并新增 schedule-level `profile_id`。wgpu host 校验 ID 非空但不读取 registry 或重新拟合任何系数。

## 验证结果

| 验证步骤 | 结果 |
|---|---|
| Matrix binary 编译与真实 timestamp 采样 | 通过 |
| Registry 生成 | 通过 |
| 精确匹配 `noir-vulkan-gpu-matrix-v1` | 通过 |
| 不存在目标 ID 的 static 回退 | 通过 |
| profile 驱动 Scene 由 wgpu host 消费 | 通过 |
| 局部 Render Schedule / 全 Scene oracle readback | 完全一致 |
| Host layout solver calls | 0 |

`tools/verify_profile_registry.sh` 可一键重现精确选择、回退和 host consumption 三项断言。

## 运行方式

```bash
cd wgpu-verify
XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime WGPU_BACKEND=vulkan \
  cargo run --release --bin calibrate_matrix -- ../profiles/registry.json

cd ..
PLTCOLLECTS="$PWD:/usr/share/racket/collects" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
  racket tools/export-dashboard.rkt out/registry-match.scene.json

./tools/verify_profile_registry.sh
```

## 下一步

当前 registry 在本环境只有一个实测 profile。下一步应把 matrix 带到真实 Vulkan/Metal/D3D12/WebGPU 设备上，收集 profile 组；随后实现**profile provenance 与有效期**，将 driver 版本、wGPU 版本、compiler revision、采样日期与 profile schema version 一同冻结，防止陈旧基准静默影响新环境的 Render Strategy。
