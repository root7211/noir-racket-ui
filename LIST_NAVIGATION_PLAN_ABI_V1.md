# Noir List Navigation Plan ABI v1

**状态：** Draft implementation contract  
**规范标识：** `noir-list-navigation-plan-v1`，revision `1`  
**依赖：** `noir-virtual-list-plan-v1@1`、`noir-scrollbar-plan-v1@1`；二者仅可被引用，不能被重新定义。

> `list_navigation_plan` 将四个键盘事件编译为对既有 viewport domain 的有限状态转换。运行期不执行逐行循环、UI tree 查询、几何计算、text shaping、GPU 分配或 packet worklist 构造。

## 1. Scene ABI

顶层 `abi_contracts` 必须增加：

```json
"list_navigation_plan": {
  "schema": "noir-list-navigation-plan-v1",
  "revision": 1
}
```

每一个 `list_navigation_plans[]` 元素必须携带同样的 `abi_schema` 与 `abi_revision`，并使用下表字段。

| 字段 | 类型 | v1 固定语义 |
|---|---|---|
| `id` | string | navigation plan 的唯一 compiler ID。 |
| `list_id` | string | 精确引用一个 `virtual_list_plan.id`。 |
| `scrollbar_id` | string | 精确引用同一 list 的 `scrollbar_plan.id`；用于固定 thumb sync binding。 |
| `page_step` | unsigned integer | 精确等于引用 list 的 `visible_rows`。 |
| `max_viewport` | unsigned integer | 精确等于 `logical_capacity - visible_rows`。 |
| `transitions` | array | 恰有 `page-up`、`page-down`、`home`、`end` 四项，固定顺序。 |
| `transitions[].key` | string | 精确为 `page-up`、`page-down`、`home`、`end`。 |
| `transitions[].kind` | string | `subtract-step`、`add-step-clamp`、`set-zero`、`set-max` 之一。 |
| `tile_ids` | ascending unsigned integer array | 精确等于绑定 scrollbar 的局部 tile IDs。 |
| `packet_worklist_index` | unsigned integer | v1 精确为 no-packets slot `2`。 |
| `physical_slot_rule` | string | 精确为 `logical-mod-physical-slots`。 |

## 2. Transition 定律

设当前 viewport 为 `v`，`S = page_step`，`M = max_viewport`。运行期只能执行以下已编译规则：

| Key | Target viewport |
|---|---|
| PageUp | `max(0, v - S)` |
| PageDown | `min(M, v + S)` |
| Home | `0` |
| End | `M` |

每次 transition 都使用同一固定终端路径：

```text
Key
→ list_navigation_plan transition
→ target viewport
→ scroll_compact_list_to(list_index, target)
→ fixed scrollbar thumb pos.y sync
→ RenderRequest::scroll(list_index, target)
  + RenderRequest::no_packets(local scrollbar tile mask)
```

当 target 与当前 viewport 相同，宿主只记录已证明的 boundary；不得制造新的 GPU patch、packet dispatch 或 render request。

## 3. 启动期 proof

Rust 宿主必须验证：schema/revision、ID 唯一性、list/scrollbar 双向绑定、compact direct-scroll资格、`page_step == visible_rows`、`max_viewport`、四项transition的种类和顺序、局部tile精确相等、no-packets worklist与 physical ring rule。任一不符必须在事件循环前拒绝 Scene。

## 4. Racket DSL v1

```racket
(list-navigation #:id telemetry-navigation
                 #:for telemetry-registers
                 #:scrollbar telemetry-scrollbar)
```

该 form 不接受运行期参数或自定义算式。它只向同一静态 root 中已声明的 list 与 scrollbar 建立可证明绑定；`page_step`、`max_viewport`、tile/worklist 均由编译器从冻结 artifact 推导。

## 5. v1 禁止项

| 禁止项 | 原因 |
|---|---|
| PageDown 以逐行循环实现 | 违反固定常数时间 transition。 |
| 运行期搜索对应 scrollbar 或 list | plan 中已有固定索引/ID proof。 |
| 在导航路径重新计算 thumb geometry | scrollbar plan 已拥有固定地址与映射。 |
| 新建或合并 packet worklist | navigation 与 thumb sync 均为 no-packets。 |
| 用键盘 selection 逻辑间接模拟大步导航 | selection 与 viewport 的状态域不同，必须保持独立计划。 |

## References

[1]: [Virtual list and row activation ABI v1](VIRTUAL_LIST_ROW_ACTIVATION_ABI_V1.md)  
[2]: [Scrollbar Plan ABI v1](SCROLLBAR_PLAN_ABI_V1.md)  
[3]: [Rust existing compact viewport and thumb synchronization path](wgpu-verify/src/bin/noir_winit_host.rs)
