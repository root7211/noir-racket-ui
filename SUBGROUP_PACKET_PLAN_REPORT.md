# Glyph Placement Renderer：Subgroup Packet Plan

**作者：Manus AI**

## 设计目标

本阶段把 Noir 已有的 Glyph Placement Plan 再细化为**编译期固定的 width-32 lane packet**。每一项 `subgroup-packet` 描述连续 placement range 中的一个静态 chunk；运行时不会根据文本长度、tile geometry 或 GPU thread count 推导 packet。

> 该实现将“warp/subgroup 可作为向量机”的思路落在 wgpu GUI 后端中，但不假定任何特定 GPU 一定具有 32-lane subgroup。编译期 packet width 是 Noir 当前 execution shape；宿主会根据设备能力选择 feature-gated subgroup prepass 或 ABI 等价的 packet draw fallback。[1]

## 编译期 ABI

Racket 在 `glyph-draw-packet` 之后执行 `compile-subgroup-packet-plan`。每个 glyph draw packet 被顺序切为最多 32 placement 的 chunks，并固定输出以下数据。

| 字段 | 含义 | 运行时是否推导 |
|---|---|---|
| `packet_index` | 源 glyph draw packet 的稳定地址 | 否 |
| `first_placement` | lane 0 的 placement slot | 否 |
| `lane_count` | 有效 lane 数，范围 1–32 | 否 |
| `subgroup_width` | Noir canonical 宽度，固定 32 | 否 |
| `active_lane_mask` | 低 `lane_count` 位为 1 | 否 |
| `dynamic` | 是否读取动态 glyph cell | 否 |

Command Palette 的真实 Scene 生成 4 个 packets：`[0..20)`、`[20..27)`、`[27..33)`、`[33..64)`；对应 lane counts 为 `20, 7, 6, 31`，active masks 分别是 `0x000fffff`、`0x0000007f`、`0x0000003f`、`0x7fffffff`。Racket static oracle 证明这些 ranges 连续、完整覆盖 placement buffer，并验证 tail mask 精确匹配有效 lanes。

## Rust host admission 与执行

`compiler_subgroup_packets()` 在启动期验证：dense packet index、源 glyph packet ID/dynamic parity、固定宽度 32、合法 lane count、mask/count 等式、每个 source packet 的连续 range，以及对 source placement interval 的完整覆盖。

Host 将结果压缩为 `CompiledSubgroupPacket`。全屏与 tile renderer 均直接按 packet 中的 `first_placement..first_placement+lane_count` 调用现有 Glyph Placement pipeline。tile path 只与 compiler 已给出的 `glyph_packet_range` 做两个固定整数区间裁剪；没有文本树、glyph-vs-tile geometry 或 packet search。

```text
compiler packet table
  → compiled packet lane ranges
  → fixed draw(0..6, placement_start..placement_end)
  → existing placement vertex/fragment pipeline
```

## WGSL subgroup ballot prepass

`wgpu-verify/src/host_subgroup_packet.wgsl` 提供独立、feature-gated 的 optional compute prepass。它启用 WGSL `subgroups`，以一个 32-lane workgroup 对应一个 compiler packet，调用 `subgroupAny` 判定动态 ASCII packet 是否包含非 page-1-space glyph，并由 lane 0 写出固定 packet active mask。

当前 `host_placement.wgsl` 是 vertex-instance glyph renderer。由于测试设备的 wgpu adapter 报告 `SUBGROUP_VERTEX=false`，主 pipeline 没有强制请求 subgroup feature；真实运行使用 packet draw fallback。该 fallback 仍消费同一个 compiler packet ABI，并保持与将来 compute→indirect packet path 相同的 lane range、glyph placement、page/clip/tile semantics。因而验证的是**真实 packet-aware renderer**，但并不宣称 llvmpipe 上执行了 subgroup ballot。

## 真实验证

`tools/verify_subgroup_packet_plan.sh` 导出 Command Palette Scene，在 Xvfb + winit + wgpu 中输入 `GPU → Enter`，并断言：

| 证据 | 结果 |
|---|---|
| Scene 包含 `subgroup_packet_plan`、`subgroup_width: 32`、`active_lane_mask` | 通过 |
| Rust 启动期 packet proof | 通过，4 个 width-32 packets |
| 全屏 packet-aware draw | 通过，记录每个 packet 的固定 placement range/mask |
| tile packet-aware draw | 通过，记录 tile 1 的 static/dynamic packet range |
| ASCII dynamic glyph patches 与 fixed command match | 通过，`GPU` 触发 Action Slot 0 |
| Racket 全量 regression | `0` 个 `FAILURE` |
| Rust 1.75 / wgpu 0.20 release build | 通过 |

## 可复现命令

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd .. && tools/verify_subgroup_packet_plan.sh
```

## 下一步

在具备 `wgpu::Features::SUBGROUP` 的 Vulkan adapter 上，下一步应为 `host_subgroup_packet.wgsl` 配置 packet descriptor、activity-mask storage buffer 和 indirect draw argument buffer；compute prepass 运行后，仅对 active packet 发出 indirect draw。选择该路径仍必须通过现有 startup proof 验证 packet width、mask、dynamic page-1-space predicate 与 output buffer bounds。

## References

[1] [VectorWare, “Rust SIMD on the GPU”](https://www.vectorware.com/blog/simd-on-gpu/)
