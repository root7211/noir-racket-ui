# Noir Virtual List 与 Row Activation ABI v1

**状态：** Frozen v1  
**规范标识：** `noir-virtual-list-plan-v1` 与 `noir-row-activation-plan-v1`  
**适用边界：** `#lang noir/ui` 编译器产出的 Scene JSON，以及 Rust/wgpu X11 宿主对 virtual list、row recycling、selection、scroll、row activation 的消费路径。

> 此规范冻结的不是某种组件 API，而是运行时数据流的地址和范围契约。宿主不得重新布局、遍历 UI tree、按字符串查找 action、构造 packet worklist，或根据输入扩展编译期确定的 GPU 写范围。

## 1. 版本与兼容性规则

每一个 `virtual_list_plans[]` 元素必须含有精确字段 `abi_schema: "noir-virtual-list-plan-v1"` 与 `abi_revision: 1`。每一个 `row_activation_plans[]` 元素必须含有精确字段 `abi_schema: "noir-row-activation-plan-v1"` 与 `abi_revision: 1`。两者均采用**拒绝未知主版本**策略：不同 schema 或 revision 在宿主初始化阶段必须失败，而不可静默降级、填补默认值或猜测语义。

| 演进类型 | v1 处理方式 | 允许性 |
|---|---|---|
| 新增可选字段 | 只能在未来 schema/revision 明示后加入 | 当前拒绝作为 v1 语义依赖 |
| 修改既有字段含义、单位或顺序 | 新 schema / 新 revision | 不兼容 |
| 删除字段或以 serde 默认值补全字段 | 宿主启动期拒绝 | 不允许 |
| 扩展 runtime 行为 | 只能消费 v1 已有的固定表或新增版本化工件 | 不得改写 v1 范围含义 |

Scene 顶层还必须提供 `abi_contracts`，以便宿主能够在遍历具体 artifact 前确认该 Scene 声明了同一组冻结接口：

```json
{
  "abi_contracts": {
    "virtual_list_plan": {"schema": "noir-virtual-list-plan-v1", "revision": 1},
    "row_activation_plan": {"schema": "noir-row-activation-plan-v1", "revision": 1}
  }
}
```

当两个 artifact 数组均为空时，`abi_contracts` 仍可出现；当其中任一数组非空时，`abi_contracts` 为强制字段。

## 2. `virtual_list_plan` v1

### 2.1 正式字段

| 字段 | JSON 类型 | v1 语义 | 必须满足的不变量 |
|---|---|---|---|
| `abi_schema` | string | 精确 ABI schema | 等于 `noir-virtual-list-plan-v1` |
| `abi_revision` | integer | schema 内冻结 revision | 等于 `1` |
| `id` | string | list 的唯一编译期 ID | 在 Scene 内唯一；对应 `layout_plan.id` |
| `capacity` | unsigned integer | 物理 row template / arena 容量 | 大于 0；等于所有 physical-row 地址表长度 |
| `logical_capacity` | unsigned integer | 逻辑数据域容量 | 大于 0；不小于 `visible_rows` |
| `physical_slots` | unsigned integer | recyclable physical GPU slot 数 | `1 ≤ physical_slots ≤ capacity`；recycling 时等于 `capacity` |
| `recycling` | boolean | 是否使用 logical-to-physical ring 映射 | `true` 时遵守 `logical-mod-physical-slots` |
| `visible_rows` | unsigned integer | 固定 viewport 行数 | `1 ≤ visible_rows ≤ capacity` |
| `row_height` | unsigned integer | 单行屏幕像素高度 | 大于 0 |
| `viewport_height` | unsigned integer | list viewport 屏幕高度 | 等于 `visible_rows × row_height` |
| `initial_ring_slots` | array of unsigned integer | 初始 physical→logical slot 对照 | recycling 时精确为 `[0, …, physical_slots-1]` |
| `row_ids` | array of string | physical row node ID 表 | 长度为 `capacity`；无重复；每项有匹配 layout entry |
| `row_layout_offsets` | array of unsigned integer | physical row `QuadInstance` 基地址 | 长度为 `capacity`；严格递增；与 layout entry 一致 |
| `row_instance_offsets` | array of array of unsigned integer | 每个 physical row 的 GPU quad 地址 | 长度为 `capacity`；每行非空、连续且在 resource budget 内 |
| `row_glyph_slots` | array of array of unsigned integer | 每个 physical row 的 glyph placement 槽 | 长度为 `capacity`；每行非空、连续且在 glyph budget 内 |
| `row_draw_ranges` | array of `{first,count}` | row-local quad draw range | 精确覆盖对应 `row_instance_offsets`，不得更宽 |
| `row_glyph_subranges` | array of `{first,count}` | row-local glyph placement draw range | 精确覆盖对应 `row_glyph_slots`，不得更宽 |
| `visible_row_tile_ids` | array of unsigned integer | 初始 viewport 的 row-tile 集 | 精确为 `[0, …, visible_rows-1]` |
| `scroll_transitions` | array | 静态 list 的相邻 scroll edge 表 | 非 compact table 时精确覆盖所有双向相邻 viewport edge |
| `data_register_table` | object or null | 固定容量数据表描述 | 非空时 `scroll_transitions` 必须为空，宿主走 compact ring executor |
| `data_update_batches` | array | 编译期声明的数据更新批 | 只能更新其绑定 table 的固定宽度、受限字符域记录 |
| `logical_data_ids` / `logical_labels` | arrays | recycling list 的逻辑数据审计表 | 无 compact table 时，长度精确为 `logical_capacity` |

`data_register_table`、`data_update_batches`、`logical_data_ids` 与 `logical_labels` 是 list 的**数据域扩展点**；它们不得改变 geometry、physical address、draw range、glyph range 或 row-tile 映射的 v1 含义。

### 2.2 映射和范围定律

对 recycling list，任意已选或可见 logical row `L` 的 physical slot 是唯一表达式：

```text
physical_slot(L) = L mod physical_slots
```

对 scroll 目标 `S`，可见 logical rows 是 `[S, S + visible_rows)`；可见 physical row tiles 是：

```text
[(S + i) mod physical_slots | i ∈ 0 .. visible_rows - 1]
```

宿主只能用这些已冻结的映射和 ABI 地址表来 patch y 坐标、glyph cell ID 与 row color。它不得为新的 logical row 分配 QuadInstance、GlyphCell、draw range、packet 或 tile。

## 3. `row_activation_plan` v1

### 3.1 正式字段

| 字段 | JSON 类型 | v1 语义 | 必须满足的不变量 |
|---|---|---|---|
| `abi_schema` | string | 精确 ABI schema | 等于 `noir-row-activation-plan-v1` |
| `abi_revision` | integer | schema 内冻结 revision | 等于 `1` |
| `list_id` | string | 该计划所属 list | 精确匹配一个 `virtual_list_plan.id`；每个 list 最多一个计划 |
| `action_id` | string | 审计用 action ID | 精确匹配 canonical Action Slot ID |
| `action_slot_index` | unsigned integer | Action Slot 的运行时地址 | 在 canonical `action_slots` 中有效且 ID 一致 |
| `activate_batch_id` | string | 包含 action 的已编译 coalesced batch | batch strategy 必须为 `coalesced`，且 `execution_refs` 含 `Action(action_slot_index)` |
| `tile_mask` | unsigned 64-bit integer | Action 自己的局部 damage tile mask | 精确等于 Action Plan tile mask；必须是 batch tile mask 的子集 |
| `packet_worklist_index` | unsigned integer | renderer packet activity worklist slot | 精确等于 batch composite slot；v1 限定为 slot 2 `no-packets=[]` |
| `strategy_id` | string | activation dispatcher 策略 | 精确为 `coalesced` |
| `physical_slot_rule` | string | logical row 到 physical slot 的规则 | 精确为 `logical-mod-physical-slots` |

### 3.2 运行期短路径

输入期仅允许以下确定性操作：

```text
selected logical row
→ row_activation_plan[list]
→ physical = logical mod physical_slots       // 审计与固定 row slot 关联
→ activate_batch_id
→ pre-proved winner writes
→ RenderRequest{ batch.tile_mask, coalesced, packet_worklist_index }
```

`row_activation_plan.tile_mask` 是 **Action-local scope**，而实际 batch RenderRequest 可以额外包含 pre-proved release transient tile。允许条件仅为：

```text
(batch.tile_mask & row_activation_plan.tile_mask) == row_activation_plan.tile_mask
```

这不是 runtime widening：额外 tile 已经属于同一 compiler-emitted coalesced batch，并通过 batch winner-write 与 conflict proof 固定。

## 4. 明确禁止的运行时行为

| 禁止项 | 原因 |
|---|---|
| 按 action ID 字符串查找 callback 或 HashMap | Action Slot 已固定，字符串仅保留审计用途。 |
| 根据 pointer / scroll 动态算 row layout、glyph advance、draw range 或 tile coverage | 这些均由 v1 artifact 完整提供。 |
| 合并或生成新的 packet worklist | v1 row activation 固定选择 empty `no-packets` slot。 |
| 为 list logical row 动态分配 GPU instance/glyph 资源 | logical domain 只能映射到固定 physical ring。 |
| 缺字段时用默认值“兼容旧 Scene” | 会把 ABI drift 伪装成正确运行。 |

## 5. 后续扩展保留边界

Scrollbar、PageUp、PageDown、Home 与 End 仅能新增独立、版本化的 `scrollbar_plan` 或 `list_navigation_plan`；它们必须引用 v1 list `id`、fixed geometry、viewport target domain 和同一 physical-slot rule。它们不得修改本规范的 `virtual_list_plan` 或 `row_activation_plan` 字段含义。

任何需要改变 worklist 策略、可见行映射、physical ring 规则或 row activation batch semantics 的设计都必须发布新 schema；不得把变化藏在可选 JSON 字段、宿主分支或默认值中。

## References

[1]: [Racket Scene JSON encoder](noir/ui/main.rkt)  
[2]: [Rust Scene ABI与virtual-list / row activation反向proof](wgpu-verify/src/bin/noir_winit_host.rs)  
[3]: [Row Activation端到端验证报告](ROW_ACTIVATION_REPORT.md)
