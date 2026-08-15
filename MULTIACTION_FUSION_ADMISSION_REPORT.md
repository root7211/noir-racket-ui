# Multi-Action Event 与 Compiler Fusion Admission Proof

**状态：** 已实现静态 `multi-action-event` DSL、Action Task batch lowering、compiler admission/rejection proof、Rust启动期反向验证，以及 admitted/rejected fixture 的真实 Vulkan 执行。

## 1. 目标

`commit-group` 证明了事务型多字段更新可以融合，但 Noir 还需要证明：多个彼此独立的 Action Plan 不必经由一个人为transaction，也可以由一个静态事件在编译期形成可审计的候选 batch。

> `pointer event → compiler batch ID → release transient + Action Task* → admission proof → coalesced executor`

运行时不接收动态回调列表。`multi-action-event` 的 action列表只存在于宏展开期和Scene proof中；host最终只消费已验证的 coalesced batch references。

## 2. DSL

```racket
(multi-action-event #:id refresh-all
                    #:actions (refresh-fps refresh-latency advance-progress)
                    "REFRESH ALL")
```

该构造在宏展开期内联为基础 `button`，其中第一个Action仅作为既有Event Map兼容的primary action，完整成员列表作为compiler-only `#:multi-actions` property。`compile-event-map` 验证每个Action ID均在canonical Action Slot表中存在；`compile-frame-coalesced-batches` 将 `release-<event>` 与所有Action Task按固定顺序加入同一个activate batch。

## 3. Admission Proof

`annotate-multi-action-fusion-admission` 在 task tile IDs、conflict graph、composite worklists 和最终profile strategy均固定后执行。每个多Action activate batch得到以下 proof：

| 检查 | Admitted条件 |
|---|---|
| Task membership | batch严格等于 `release` + DSL action列表 |
| Animation order | release transient 必须是稳定execution order的第一项 |
| Write conflict | Action Task两两没有byte-range重叠 |
| Tile partition | Action tile集合两两不重叠 |
| Packet scope | 每个Action Task固定为 `no-packets` slot 2 |
| Strategy | 最终compiler strategy必须为 `coalesced` |

如果任何条件不满足，proof输出 `status=rejected` 与确定原因，例如 `write-conflict`、`tile-overlap`、`packet-scope` 或 `animation-order`。拒绝不会由运行时重新裁决；batch保留普通coalesced执行语义，且不领取融合worklist slot。

## 4. Fixtures

### Admitted

`examples/multi-action-fusion-dashboard.rkt` 同时触发：

| Action | State / GPU效果 | Tile |
|---|---|---:|
| `refresh-fps` | text-run glyph patch | 0 |
| `refresh-latency` | text-run glyph patch | 1 |
| `advance-progress` | instance `size.x` patch | 2 |

其 `coalesced-activate-refresh-all` proof 为 `admitted`：conflict edges为0、所有Action worklist均为2、release先执行，最终实际execution refs为 `Transient(2), Action(0), Action(1), Action(2)`。

### Rejected

`examples/multi-action-fusion-rejected.rkt` 使用两个写集独立、但同属tile 0的Action。编译器输出：

```json
{
  "status": "rejected",
  "reason": "tile-overlap",
  "action_tile_ids": [[0], [0]],
  "conflict_edge_count": 0
}
```

这说明拒绝来自真正的tile局部性条件，而不是Action写冲突。release host仍可执行该batch的普通coalesced路径，并得到 `expectations_match=true`。

## 5. Rust反向验证

Rust `StrategySelectionProof` 现在读取 `fusion_admission`。启动期对于admitted proof重新检查：Action Task IDs、release-first顺序、Action tile IDs、packet slot 2、tile无重叠、byte-write冲突数和compiler strategy。对于rejected proof，host只接受受限原因枚举并保留正常batch执行。

同时修复了一个与新负向fixture暴露的通用host边界条件：tile scissor rect现在被裁剪至实际surface范围，避免合法Scene几何在wgpu验证层超出640×360 render target。

## 6. 验证

| 检查 | 结果 |
|---|---|
| Racket 全量回归 | 通过 |
| Admitted fixture Scene导出 | 通过，`fusion_admission.status=admitted` |
| Rejected fixture Scene导出 | 通过，`reason=tile-overlap` |
| Rust `cargo check` 与release build | 通过 |
| Admitted Scene真实 Vulkan benchmark | 通过，3个Action refs、`expectations_match=true` |
| Rejected Scene真实 Vulkan benchmark | 通过，普通coalesced fallback、`expectations_match=true` |

## 7. 下一步

本阶段将“能否融合”变成了编译期判定，但Action Task当前仍固定 `no-packets`。下一步应为Action Plan引入action-local packet worklists；然后admitted multi-action batch可以像transaction composite worklist一样生成精确packet union，并获得真正的单compute dispatch收益。拒绝proof则继续保留多个action-local请求，形成可直接量化的普通Action baseline。
