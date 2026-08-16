# `modal_focus_subgraph v1` ABI 规范

**状态：** 已实现并以真实 X11/Vulkan 验证。
**Schema：** `noir-modal-focus-subgraph-v1@1`。
**作者：** Manus AI。

## 1. 目的与边界

`modal_focus_subgraph v1` 为已经由 `overlay_state_plan v1` 管理可见性的受限 Material overlay 提供**编译期固定的键盘焦点子图**。它不创建通用焦点管理器，不遍历组件树，不根据几何查找下一个目标，也不允许运行时修改 Tab 顺序。

该计划只适用于二元 `0/1` overlay 状态。当 overlay 打开时，`Tab` 与 `Shift+Tab` 只能沿编译器生成的有限环移动；`Enter` 只能激活该环中当前固定 event slot；`Escape` 沿既有 overlay close action 关闭弹层。关闭后，运行时恢复预声明的 open event 上下文。[1] [2]

| 属性 | v1 合同 |
|---|---|
| overlay 数量 | 每个 Scene 可含有限个已声明的 modal entry；每个 entry 有唯一 ID。 |
| Tab 目标数 | 每个 entry 为 2–6 个唯一的可键盘激活 close event。 |
| 背景隔离 | open event 不得进入 `allowed_event_slots`；打开时 Tab/Shift+Tab/Enter 不会进入背景 Focus Graph、列表或键盘命令。 |
| scrim | 允许保留在 `allowed_event_slots` 中供 pointer dismiss 使用，但不是 Tab target。 |
| 运行时状态 | 每个 entry 仅保存一个当前环索引；其余所有 slot、边、tile 与动作均不可变。 |
| 可写GPU范围 | 不新增任何范围；继续使用关联 `overlay_state_plan` 已证明的 alpha patch 与 tile mask。 |

> **定义。** “恢复”在 v1 中是恢复 `restore_event_slot` 所代表的预声明打开控制上下文；它不是运行时 DOM/组件树焦点搜索。

## 2. Racket 声明形式

v1 的实际用户级声明嵌入现有 `material-overlay-state`。`#:modal-focus` 的字面顺序就是 Tab 的正向环顺序：

```racket
(state [overlay-visible 0])
(action overlay-open    (set overlay-visible 1))
(action overlay-confirm (set overlay-visible 0))
(action overlay-dismiss (set overlay-visible 0))
(action overlay-pin     (set overlay-visible 0))
(action overlay-copy    (set overlay-visible 0))
(action overlay-export  (set overlay-visible 0))

(material-overlay-state #:id deployment-overlay
                        #:state overlay-visible
                        #:initial 0
                        #:open-on overlay-open
                        #:close-on (overlay-confirm overlay-dismiss
                                    overlay-pin overlay-copy overlay-export)
                        #:modal-focus (deployment-confirm deployment-dismiss
                                       menu-pin menu-copy menu-export)
  ...)
```

此 fixture 的完整可执行版本位于 [`examples/material-overlay-showcase.rkt`](examples/material-overlay-showcase.rkt)。[1]

宏展开期必须拒绝以下输入：未声明的状态或动作；不是 literal `set state 1/0` 的 open/close action；没有唯一 open event 的 overlay；少于 2 或多于 6 个目标；重复目标；scrim 作为 Tab target；以及不属于该 overlay 的 event。

## 3. Scene JSON ABI

Scene 顶层新增两个字段：

```json
{
  "modal_focus_subgraph_required": true,
  "modal_focus_subgraph_plan": {
    "abi_schema": "noir-modal-focus-subgraph-v1",
    "abi_revision": 1,
    "entries": [
      {
        "id": "deployment-overlay",
        "state": "overlay-visible",
        "state_index": 0,
        "restore_event_slot": 0,
        "focus_event_slots": [3, 2, 4, 5, 6],
        "next_slots": [2, 4, 5, 6, 3],
        "previous_slots": [6, 3, 2, 4, 5],
        "allowed_event_slots": [1, 2, 3, 4, 5, 6],
        "tile_ids": [0]
      }
    ]
  }
}
```

`modal_focus_subgraph_required` 只能由成功的 `#:modal-focus` lowering 产生。若该标记为 `true` 而计划被替换为 `false`，Rust 宿主必须在创建 GPU 资源和事件循环前拒绝 Scene。没有 modal 声明的普通 Scene 显式导出 `false`，保持兼容性。[2] [3]

## 4. 固定状态转移

下表是 `deployment-overlay` 的实际编译器产物。slot 1 是可点击的 scrim dismiss；它保留在允许 pointer 集合中，但不会成为键盘环目标。

| 当前条件 | 输入 | 固定执行 | 下一个焦点/状态 |
|---|---|---|---|
| `overlay-visible = 0` | event 0 / `overlay-open` | 既有 batch 写入状态=1，overlay alpha endpoint=visible，环索引=0 | event 3 / `deployment-confirm` |
| `overlay-visible = 1` | `Tab` | `current_index = next_slots[current_index]` | `3 → 2 → 4 → 5 → 6 → 3` |
| `overlay-visible = 1` | `Shift+Tab` | `current_index = previous_slots[current_index]` | 逆向同一环 |
| `overlay-visible = 1` | `Enter` | 激活当前环 event 的既有固定 batch；对应 close action 令状态=0 | slot 0 的预声明恢复上下文 |
| `overlay-visible = 1` | `Escape` | 选择该 overlay 唯一 admitted close event，执行既有 close batch | slot 0 的预声明恢复上下文 |
| `overlay-visible = 1` | scrim pointer | 仅 event 1 / `overlay-dismiss` 可命中 | 状态=0；无Tab环搜索 |

## 5. Rust 启动期 proof

宿主接受计划前必须反向验证：schema/revision；required 标记；唯一 entry ID；state slot 与 admitted overlay state entry 一致；唯一 open event；2–6 个唯一 Tab target；canonical正反环边；所有 Tab target 都是 overlay close action；`allowed_event_slots` 精确等于 scrim 加 close event 的固定集合；以及 modal tile mask 与 overlay tile mask 完全相同。[3]

验证通过后，宿主仅保留紧凑结构：

```rust
CompiledModalFocusSubgraphEntry {
    state_index,
    restore_event_slot,
    focus_event_slots,
    next_slots,
    previous_slots,
    allowed_event_slots,
    tile_mask,
    current_index,
}
```

运行时不保留高层组件ID到节点树的映射，也不执行焦点发现或重排。[3]

## 6. 明确非目标

v1 不包括通用焦点可视ring、自由嵌套modal、跨窗口焦点、动态插入/删除目标、ARIA/平台可访问性桥接、IME焦点或任意循环图。这些能力应建立在同样的编译期固定子图合同之上，而不是放宽本ABI。

## References

[1] [Material overlay showcase fixture](examples/material-overlay-showcase.rkt)
[2] [Racket Scene ABI、modal lowering 与 JSON serializer](noir/ui/main.rkt)
[3] [Rust proof 与键盘执行器](wgpu-verify/src/bin/noir_winit_host.rs)
