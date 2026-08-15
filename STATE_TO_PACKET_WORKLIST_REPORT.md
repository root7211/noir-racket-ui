# State-to-Packet Worklist Lowering

**作者：Manus AI**

## 概要

本阶段将 packet activity compute 从“每次 dispatch 全部 subgroup packets”降低为“按 compiler-selected packet worklist dispatch”。Racket 的 `subgroup_packet_plan` 已经完全确定 dynamic glyph placement 与 packet ID；因此 host 不应在运行时扫描 state、glyph ranges 或 glyph storage 来寻找变化 packet。

Scene 现在包含两条 canonical worklists：

| Worklist | Index | Compiler packet IDs | 用途 |
|---|---:|---|---|
| `all-packets` | 0 | `[0, 1, 2, 3]` | 初始/全屏 replay 与 full canvas |
| `dynamic-packets` | 1 | `[2]` | keyboard ASCII mutation、Command Matcher tile redraw |

Racket 在 macro expansion 期证明 all list 对 packet table 稠密覆盖、dynamic list 无重复、dynamic list 精确等于 `dynamic?` packet closure。

## Scene 与 Worklist ABI

运行时 `packet-worklist` artifact 为：

```racket
(packet-worklist index id packet-indices)
```

Scene JSON 明确导出 `packet_worklists`，使 Rust 在启动期验证 dense index、canonical IDs、packet bounds、去重和动态依赖闭包。该列表不是调度提示；它是 host activity compute dispatch 唯一允许使用的 packet 地址来源。

## WGSL 与 Rust 执行

由于 llvmpipe/downlevel compute stage 限制为 4 个 storage buffers，worklist 不占第五个 storage binding，而是编码为固定 160-byte uniform payload：`count + padding + 8 × vec4<u32>`，最多容纳 32 packet IDs。WGSL 读取：

```wgsl
let packet_index = packet_worklist.lanes[group.x / 4u][group.x % 4u];
```

因此 workgroup `i` 只会访问 compiler worklist 的 `i` 号 packet。Rust 每次 task dispatch 仅向预分配 uniform buffer 写 compiler-proved packet indices，并执行 `dispatch_workgroups(worklist.len(), 1, 1)`。没有范围搜索、hash lookup 或 glyph/state-to-packet 推导。

| Render/task path | Worklist | Activity compute workgroups |
|---|---|---:|
| Initial full canvas | `all-packets` | 4 |
| Full replay | `all-packets` | 4 |
| ASCII `G` / `P` / `U` tile update | `dynamic-packets` | 1 |
| Command Matcher `GPU → Enter` tile update | `dynamic-packets` | 1 |

完整 static glyph packets 的 indirect commands 在全量 compute 时已被写入；动态 task 只重算可能因 page-1-space predicate 改变的 packet 2。Tile renderer 仍按照 compiler scissor/range plan 绘制，不重新推导 packet geometry。

## 真实验证

`tools/verify_packet_worklists.sh` 导出 Command Palette，执行 `G → P → U → Enter`，并检查：

1. Scene JSON 包含 `all-packets=[0,1,2,3]` 与 `dynamic-packets=[2]`。
2. 初始 canvas 使用 4 个 workgroups。
3. 每次 ASCII glyph patch 与 command action tile redraw 使用 dynamic worklist，恰好 dispatch 1 个 workgroup。
4. tile 1 的 dynamic packet 2 继续使用 compiler fixed indirect offset 32。
5. `GPU` 仍命中 Action Slot 0。

Racket 全量 regression 为 `0` 个 `FAILURE`；Rust 1.75 / wgpu 0.20 release build 与 Xvfb/winit/wgpu oracle 均通过。

## 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd .. && tools/verify_packet_worklists.sh
```

## 后续

下一步可把 worklist 从全局 `dynamic-packets` 进一步细化为 field/action/transaction-local lists，例如 command field `[2]`、settings group `[4,5,6]`。不应在 host 中计算这些列表；Racket 应从 State Slot、Glyph Placement、Action Slot 与 Transaction Plan 的编译期依赖关系生成它们。
