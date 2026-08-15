# GPU-driven Packet Activity → Indirect Draw Plan

**作者：Manus AI**

## 概要

本阶段将 Noir 的 Glyph Placement Subgroup Packet Plan 推进为真正的 GPU-driven submission 路径。Racket 不仅输出固定 32-lane packet，还为每个 packet 指定稳定的 activity word 和 16-byte `DrawIndirect` command 地址；WGSL compute prepass 写入 activity mask 与 indirect command；宿主随后只提交这些 compiler-addressed indirect commands。

运行时不检查文本树、不计算 glyph bounds、不重新组织 draw packets，也不为动态文本分配 command buffer。变化仅来自预分配 glyph storage 的 page-1-space/non-space 状态。

## 编译期 ABI

每个 `subgroup-packet` 现在包含两个额外的 GPU 地址。

| 字段 | 固定规则 | 用途 |
|---|---:|---|
| `activity_word_offset` | `packet.index` | activity storage buffer 的 `u32` 地址 |
| `indirect_byte_offset` | `packet.index × 16` | `DrawIndirect` command byte offset |
| `subgroup_width` | `32` | compute workgroup/lane execution shape |
| `active_lane_mask` | `(1 << lane_count) - 1` | packet static valid-lane mask |

Command Palette 产生 4 个 packets，因此 indirect byte offsets 固定为 `0, 16, 32, 48`。Racket static oracle 同时验证连续 placement ranges、lane counts、tail masks、activity offsets 与 indirect offsets。

## WGSL compute prepass

`wgpu-verify/src/host_packet_activity.wgsl` 定义 one-packet/one-workgroup 的 portable compute pipeline：

1. 每个 workgroup 固定为 32 invocations，对应一个 compiler packet。
2. 每个 lane 读取自己固定的 glyph word；静态 packet 恒为 active，动态 packet 仅在存在非 page-1-space glyph 时 active。
3. workgroup lane 0 对固定 `[0, lane_count)` 做 deterministic reduction。
4. lane 0 写 `activity_masks[packet_index]`，并写出 `{ vertex_count=6, instance_count=0|lane_count, first_vertex=0, first_instance=first_placement }`。

该 shader 是 wgpu 0.20/llvmpipe 可执行的 shared-workgroup fallback。现有 `host_subgroup_packet.wgsl` 仍提供 feature-gated `subgroupAny` ballot 版本；两者消费相同的 compiler packet ABI，并且输出相同的 activity/indirect layout。

## Rust submission

Rust 启动期验证 Scene packet 的 dense index、mask/count、源 glyph packet 覆盖，以及 `activity_word_offset=index`、`indirect_byte_offset=index×16`。随后 host 创建四个固定资源：packet descriptor storage、activity storage、indirect storage/indirect buffer、compute bind group/pipeline。

每次 full replay、full canvas 或 selected-tile redraw，host 先在同一 command encoder 中编码 compute prepass。全屏 glyph rendering 对每个 packet 调用 `draw_indirect(indirect_buffer, offset)`。tile rendering 只有在 compiler tile range 完整覆盖一个 packet 时才调用 indirect draw；若 tile slice 截断 packet，则仍使用该 compiler-given clipped direct subrange，以免 indirect draw 越过 scissor-culling plan。

| 执行情形 | GPU submission |
|---|---|
| Full canvas packet | fixed `draw_indirect` |
| Tile includes full packet | fixed `draw_indirect` |
| Tile cuts packet | fixed direct subrange；不做 runtime geometry search |
| Empty dynamic packet | compute 写 `instance_count=0`，indirect draw no-op |

## 真实验证

`tools/verify_gpu_packet_activity.sh` 在 Xvfb + winit + wgpu 中导出 Command Palette Scene，输入 `GPU → Enter`，并严格验证：

| 检查 | 结果 |
|---|---|
| Scene activity/indirect offsets | 通过：首 offset 为 0，末 command offset 为 48 |
| GPU compute dispatch | 通过：4 packets、workgroup size 32 |
| Full indirect draw | 通过：包括 dynamic packet 2，offset 32 |
| Tile indirect draw | 通过：tile 1 的 page-1 dynamic packet 2，offset 32 |
| ASCII glyph updates + fixed command matcher | 通过：`GPU` 命中 Action Slot 0 |
| Racket regression | `0` 个 `FAILURE` |
| Rust 1.75 / wgpu 0.20 release build | 通过 |

## 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd .. && tools/verify_gpu_packet_activity.sh
```

## 下一步

下一阶段可以在具有 `wgpu::Features::SUBGROUP` 的 Vulkan adapter 上实际选择 `host_subgroup_packet.wgsl` 的 ballot variant，并将 activity buffer 接入 packet-level GPU timestamps。前提是保持当前 compiler packet offsets、output buffer bounds、page-1-space predicate 与 indirect command equivalence proof 不变。
