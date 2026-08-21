# Workbench Cross-View Transaction Plan v1

## 目标与状态

`workbench_cross_view_transaction_plan v1` 是 Material observability workbench v2 的**编译期限定事务产物**。它描述唯一允许的跨视图确认路径：Alerts resident view 中的固定 `Acknowledge` 事件，以字面量 `+1` 更新确认计数状态，并预声明其对 Alerts 行颜色、Alerts detail glyph 与 Overview 计数 glyph 的写入权限。

> v1 不是通用事件总线、组件查询器或跨视图状态管理器。它只把一个已知 Alerts 数据arena 与一个已知 Overview 动态文本端点压缩为不可扩张的静态写集。

本文件定义的是 Racket compiler ABI、Rust ABI gate/proof及其**固定执行器**。Rust 宿主采用object-or-false合同反序列化该计划，并在任何可见GPU渲染状态建立前验证schema/revision、required门禁及其对workbench v2、Alerts arena、Overview动态字形、action/state/event/tile见证的关联。通过后，宿主仅保留已证明的索引、地址和tile mask；Alerts行激活或固定Acknowledge事件可提交唯一跨视图确认事务。

| 属性 | 冻结值 |
|---|---|
| JSON schema | `noir-workbench-cross-view-transaction-plan-v1` |
| ABI revision | `1` |
| Scene字段 | `workbench_cross_view_transaction_plan` |
| required门禁 | `workbench_cross_view_transaction_required` |
| admitted source | `observability-alerts` resident view 的一枚已声明 data view |
| admitted target | `observability-overview` resident view 的一枚动态计数字符串 |
| action语义 | `(set state (+ state 1))`，且增量必须为字面量 `1` |
| 宿主状态 | ABI gate、启动期关联proof与固定state/GPU patch执行器均已实现。 |

## 受限宏语法

```racket
(workbench-cross-view-transaction
 #:id workbench-acknowledge-alert-transaction
 #:action workbench-acknowledge-alert
 #:from (alerts-data-view observability-alert-stream alerts-view observability-alert-detail)
 #:to (overview-view overview-alert-ack-count)
 #:state workbench-alert-ack-count
 #:delta 1)
```

该声明必须与同一 `noir-app` 内的 `material-observability-workbench v2` 共存。`#:from` 的四元组精确指定 source data-view、virtual-list、resident view 和 log-browser detail text；`#:to` 的二元组精确指定 Overview resident view 以及动态计数文本。宏不会按名称模糊匹配、遍历运行时树或推断父子关系。

## 导出对象

运行时 Scene JSON 导出一个对象或 `false`：

```text
workbench_cross_view_transaction_plan = {
  abi_schema, abi_revision,
  id, action_id, action_slot_index, event_slot,
  state, state_index, delta,
  source_data_view_id, source_list_id, source_view_id,
  source_row_color_offsets,
  source_detail_node_id, source_detail_glyph_offsets,
  target_view_id, target_count_node_id, target_count_glyph_offsets,
  tile_ids
}
```

| 字段族 | 编译期反向见证 |
|---|---|
| `action_id`、`action_slot_index`、`event_slot` | action 必须有唯一 canonical slot，且唯一 Event Map 事件指向该 action。 |
| `state`、`state_index`、`delta` | action 必须精确为同一 state 的 `add +1`；目标动态文本也必须绑定同一 state。 |
| `source_*` | data-view、virtual-list、log-browser detail 和每个 row color lane 必须属于同一 Alerts arena。 |
| `target_*` | target text 必须属于 Overview view，且其动态glyph range必须是 action plan 的固定text update。 |
| `tile_ids` | `source data-view tile ∪ source detail tile ∪ action tile ∪ target count tile` 的排序去重并集。 |

## 宏展开期拒绝规则

编译器在 Scene 导出前拒绝以下情况：多于一个事务声明；没有 workbench v2；非Alerts source 或非Overview target；source list/view 与 data-view不一致；source与target相同；动作不存在、不是`add`、状态不匹配或delta不是`1`；没有唯一Event Map slot；没有对应log-browser detail；目标不是绑定同一状态的动态文本；资源不属于声明resident subtree；row color lane不属于Alerts已证明instance集合；以及任一来源没有可用render tile。

这些拒绝使运行时未来只能消费已经固定的地址表，而不能通过额外查找扩大写集。

## 当前workbench fixture的编译产物

`examples/material-observability-workbench.rkt` 的导出计划固定以下范围：

| 资源 | 当前编译产物 |
|---|---|
| source data view | `alerts-data-view` / `observability-alert-stream` / `alerts-view` |
| source物理行颜色字段 | 3 个 `QuadInstance` color lanes |
| source detail | `observability-alert-detail`，29 个 glyph cell地址 |
| target | `overview-alert-ack-count`，8 个预分配动态glyph cell地址 |
| 状态转换 | `workbench-alert-ack-count += 1` |
| render范围 | 已证明的局部tile并集；当前固定画布产物为 tile `0` |

## Rust ABI gate与后续执行器边界

Rust 宿主已把该计划接入统一ABI合同表、Scene object-or-false反序列化和required门禁。在workbench v2、Alerts data-view、list interaction、log-browser及Overview glyph placement已经被证明后，启动期关联proof反向验证action slot、state slot、唯一Event Map slot、data-view ownership、3个row color lane、29个detail glyph、8个Overview count glyph及tile并集。`abi`、`disable`、`action`和`target`四类非canonical Scene均会在首次可见渲染前被拒绝。

固定执行器现已由Alerts active-view门禁触发。它只读取当前选择的Alerts逻辑行，以固定物理槽规则选择一条颜色lane；随后提交一枚state写入、该颜色lane、29个source detail glyph、8个Overview count glyph，并仅排入已证明tile并集的`no-packets`局部重绘。Alerts行激活和固定Acknowledge事件都在通用coalesced batch之前被截获，防止同一canonical action产生第二次非事务写入。任何不满足active view、存在选择、整数不溢出或固定glyph宽度条件的调用都会被消费为零写入。

## 验证

Racket全量语言回归冻结本ABI对象、required门禁、source/target IDs、状态与动作、3个source颜色字段、29个source detail glyph、8个target计数字glyph、canonical action/state slot及tile并集。`tools/verify_workbench_cross_view_transaction_abi_gate_v1.sh` 执行Rust 1.87 release构建、真实X11/Vulkan启动proof及`abi`、`disable`、`action`、`target`四类拒绝回归；`tools/verify_workbench_cross_view_transaction_executor_v1.sh` 额外验证合法一次性提交、无选择零写入、非活动view零写入、截图与rounded兼容。workbench Scene 包含 `workbench_cross_view_transaction_required: true`。

```bash
cd /home/ubuntu/noir_review/noir-racket-ui-statistical-analysis
PLTCOLLECTS="$PWD:" racket tests/run.rkt
NOIR_ENTRY_MODULE=examples/material-observability-workbench.rkt \
  PLTCOLLECTS="$PWD:" racket tools/export-dashboard.rkt \
  out/material-observability-workbench-v2.scene.json
bash tools/verify_workbench_cross_view_transaction_executor_v1.sh
```

## 非目标

v1 不实现通用跨视图事务、任意多写入state、第三数据arena、动态动作发现、运行时视图查询、可变长度写集、撤销/重做、持久化、异步I/O或性能测试。固定GPU patch执行器及真实X11/Vulkan事务**执行**已经验证；后续功能必须以新增的独立、受限ABI实现，不能扩大本计划的写集。
