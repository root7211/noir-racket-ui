# Log Browser Plan ABI v1

`log-browser-plan` 是运行在已冻结 `virtual_list_plan`、`row_activation_plan`、`scrollbar_plan` 与 `list_navigation_plan` 之上的**应用层计划**。它不改写任何列表ABI字段，而是将日志记录的固定文本布局、level颜色、tail append batch和selected-row详情写入预先确定的GPU地址。

| 字段 | 类型 | v1约束 |
|---|---|---|
| `abi_schema` / `abi_revision` | string / u32 | 必须为 `noir-log-browser-plan-v1` / `1`。 |
| `id` | string | 场景内唯一的日志浏览器标识。 |
| `list_id` | string | 必须引用一个已冻结的compact `virtual_list_plan`。 |
| `append_batch_id` | string | 必须引用同一table内一个 `trigger=manual` 的data-update batch。 |
| `append_indices` | usize[] | 必须是严格递增、连续的tail区间，并以`logical_capacity-1`结束。 |
| `detail_node_id` | string | 必须引用一个固定glyph placement范围的静态文本节点。 |
| `detail_glyph_offsets` | usize[] | 固定、严格递增、4-byte对齐的glyph ID写入地址。 |
| `detail_tile_ids` | usize[] | 详情节点覆盖的编译期tile集合。 |
| `row_color_offsets` | usize[] | 物理row slots的固定QuadInstance color地址；引用list interaction plan。 |
| `levels` | level/color[] | 编译期有限表：`INFO`、`WARN`、`ERROR`、`DEBUG`四种固定颜色。 |
| `packet_worklist_index` | usize | 必须是固定 `no-packets` slot `2`。 |

每条记录为固定宽度大写ASCII字符串，语义列顺序为 `LEVEL | TIME | SOURCE | MESSAGE`，通过编译期固定空格边界形成四列。`LEVEL` 占记录前五个字符，运行时只在有限level表中选择已经编译好的row颜色。选择状态优先于level背景色；失去选择或滚动后，由该计划重新恢复相应level颜色。

Manual append不会接受任意输入值。宿主只可按`append_batch_id`执行Scene内已验证的更新集合；值、index、宽度、tail区间与no-packets局部写入范围均在启动期proof。详情面板只写 `detail_glyph_offsets`，不会动态shaping或创建glyph资源。
