# Field/Action/Transaction-local Packet Worklist Lowering

**作者：Manus AI**  
**状态：已实现并完成 Racket、Rust release 与真实 X11/wgpu 验证**

## 目标

本阶段将 Noir 的 GPU packet activity prepass 从全局动态集合进一步降低为**状态转换级的最小 packet worklist**。编译器已掌握 keyboard transition、focus field、transaction field slots、glyph cell ranges 与 subgroup packet membership 的静态依赖，因此运行时不应再扫描全局 `dynamic-packets`。

运行时路径现在为：

> `keyboard / command / transaction task → compiler-fixed worklist index → fixed uniform payload → packet activity compute dispatch(K) → activity/indirect buffers → tile render`

其中 `K` 是编译期确定的受影响 packet 数量；对于无 glyph 写入的路径，`K = 0` 并且不编码 compute pass。

## 编译期 ABI

Racket 的 `compile-packet-worklists` 现在在既有 all/dynamic 基线之外生成三类固定列表。

| Worklist 类别 | ID 形式 | 作用 | 运行时行为 |
|---|---|---|---|
| 全量 | `all-packets` | 初始 canvas/full replay | dispatch 全部 packet |
| 动态兼容基线 | `dynamic-packets` | 向后兼容、全局动态刷新 | dispatch 全部 dynamic packet |
| 空列表 | `no-packets` | caret、focus 或 instance-only visual task | 跳过 compute |
| Field-local | `field-<node>` | digit/ASCII insert、Backspace、Escape、单 field commit | 仅 dispatch 该 field packet |
| Transaction-local | `transaction-<id>` | commit-group、Apply All、Reset All | dispatch transaction 成员 packet 并集 |

编译期证明要求所有 worklist index 稠密、ID 唯一、packet index 不越界且列表无重复。`all-packets` 必须覆盖 subgroup packet table；`dynamic-packets` 必须精确等于 dynamic packet closure；`no-packets` 必须为空。

### Command Palette 输出

| Index | Worklist | Packets |
|---:|---|---|
| 0 | `all-packets` | `[0, 1, 2, 3]` |
| 1 | `dynamic-packets` | `[2]` |
| 2 | `no-packets` | `[]` |
| 3 | `field-command-entry` | `[2]` |

因此 `G/P/U` transition 和 `GPU → Enter` 都只重算 packet 2。

### Settings Form 输出

| Index | Worklist | Packets |
|---:|---|---|
| 0 | `all-packets` | `[0,1,2,3,4,5,6,7,8,9]` |
| 1 | `dynamic-packets` | `[3,6,9]` |
| 2 | `no-packets` | `[]` |
| 3 | `field-sample-interval-row$field` | `[3]` |
| 4 | `field-alert-threshold-row$field` | `[6]` |
| 5 | `field-batch-size-row$field` | `[9]` |
| 6 | `transaction-apply-all` | `[3,6,9]` |

## Rust/WGSL 执行结构

Rust 在 `compiler_packet_worklists` 中保留 Racket `SubgroupPacketEntry.index` 这个**dense subgroup packet index**，而不是混用 source glyph-draw packet index。这个区分是必需的：一个 source glyph draw packet 可被分割为多个 subgroup packet。

启动期将 field 和 transaction list 压缩为两个固定数组：

```rust
keyboard_packet_worklist_indices: Vec<usize>,
transaction_packet_worklist_indices: Vec<usize>,
pending_packet_worklist: usize,
```

键盘 transition、Escape、single-field commit、Command Matcher 命中、commit-group 和 pointer Apply/Reset 都只向 `pending_packet_worklist` 写入预验证的数组 index。`redraw_selected_tiles` 用 `mem::replace(..., no_packets_index)` 消费该 index，因此一次 tile redraw 不会泄漏到下一次任务。

为了兼容当前 llvmpipe 在 compute stage 的四个 storage-buffer 限制，worklist 不使用第五个 storage buffer，而是编码在固定 160-byte uniform payload。WGSL 使用：

```wgsl
let packet_index = worklist.lanes[group_id.x / 4u][group_id.x % 4u];
```

因此 workgroup ID 只是一条 compiler-fixed worklist 的序号，而不再等同于 packet ID。`no-packets` 的 list 长度为零时，Rust 记录：

```text
packet-activity-skip worklist=no-packets index=2 packets=[] reason=compiler-empty
```

并直接返回，不创建 compute pass、不写 activity/indirect buffers。

## 验证

| 验证项 | 结果 | 关键证据 |
|---|---|---|
| Racket 全量回归 | 通过，`FAILURE=0` | Scene worklists 与 static oracle |
| Rust 1.75 / wgpu 0.20 release build | 通过 | local index arrays 与 uniform ABI |
| Command Palette X11/wgpu | 通过 | 初始 `[0,1,2,3]`，`G/P/U` 与 matcher `[2]` |
| Settings Form X11/wgpu | 通过 | field worklists `[3]`、`[6]`、`[9]`；Apply All `[3,6,9]`；empty skip |

真实测试脚本分别为 `tools/verify_packet_worklists.sh` 与 `tools/verify_settings_form.sh`。两者运行 Xvfb、真实 winit 事件和真实 wgpu renderer，而不是模拟 host API。

## 语义边界

本阶段只缩小 activity compute 的 workgroup 集合；glyph placement、indirect command offsets、tile scissor、State Slot、Action Slot、Transaction Slot 与 subgroup differential contract 均保持不变。编译器选择 worklist，不让运行时搜索 glyph ranges、nodes、state names 或 packet bounds。

下一步可将 worklist index 进一步写入 Frame Task / Coalesced Batch 的所有 transient task 记录，令 hover/pressed/release、animation tick 与 pointer action 的 packet activity决策也完全由 task IR 一次性携带。 
