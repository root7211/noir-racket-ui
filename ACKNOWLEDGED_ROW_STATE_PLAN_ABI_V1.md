# `acknowledged_row_state_plan v1`

## 目标

`acknowledged_row_state_plan v1` 为应用层 `noir-workbench/app` 生成的 Alerts 数据arena提供一个**固定容量、二值、按逻辑行寻址**的确认状态域。它解决已有确认事务仅修改当前物理行和Overview计数、却尚不能在滚动recycle后恢复已确认视觉状态的问题。

该计划不引入通用存储、动态schema、哈希表或运行时组件查找。它只允许一个编译期封闭的数据域：Alerts 逻辑行的 `open | acknowledged` 状态。

## 应用层语法

应用作者不声明容量、word数、状态槽、物理颜色offset或tile。v1只在 Alerts 声明上暴露业务意图：

```racket
(noir-workbench/app
 #:id operations
 #:title "Operations workbench"
 (systems #:seed "INFO  TIME  CORE  STARTUP")
 (alerts #:seed "WARN  TIME  EDGE  RETRY" #:row-state acknowledged))
```

省略 `#:row-state` 时仍采用 `acknowledged`；该默认值使 v1 应用层工作台始终拥有可恢复的确认语义。其它状态名称、三值域、自定义颜色、裸容量和用户给出的资源地址全部拒绝。

| Profile | Alerts逻辑容量 | 状态域 | 状态word数 | 可见物理槽 |
|---|---:|---|---:|---:|
| `standard` | 2,048 | `open | acknowledged` | 32 × `u64` | 3 |
| `compact` | 512 | `open | acknowledged` | 8 × `u64` | 3 |

## ABI

Scene导出字段为 `acknowledged_row_state_plan` 和 `acknowledged_row_state_required`。其schema为 `noir-acknowledged-row-state-plan-v1@1`，记录固定的：

| 字段 | 编译期证明含义 |
|---|---|
| `data_view_id` / `list_id` / `owner_view_id` | 状态域仅属于唯一Alerts data-view及其resident view。 |
| `logical_capacity` / `word_bits` / `word_count` | 每个逻辑行映射为一位；`word_count = ceil(capacity / 64)`。 |
| `acknowledge_action_id` / `action_slot_index` | 唯一确认动作能够将选中逻辑行置为`acknowledged`。 |
| `row_color_offsets` | 恢复当前可见物理行颜色的唯一固定lane集合。 |
| `detail_glyph_offsets` | Alerts详情文本的预分配glyph端点。 |
| `tile_ids` | 所有确认与recycle恢复重绘的固定tile并集。 |

## Lowering 与恢复规则

确认动作的逻辑状态写为：

```text
word = selected_logical_row / 64
bit  = selected_logical_row % 64
ack_words[word] |= 1_u64 << bit
```

列表滚动或recycle到逻辑行 `i` 时，执行器仅查询该固定word表的第`i`位，并向对应物理槽的既证明颜色lane写入 `open` 或 `acknowledged` 端点。它不扫描记录、不重新解析文本，也不访问其它data arena。

> 当前交付范围只完成该计划的Racket ABI、应用层宏展开和Scene proof。Rust启动期gate、word表存储、确认state写、recycle恢复执行器与真实X11滚动验证属于后续宿主阶段。

## 非目标

v1不支持撤销、任意标签集合、每行自由颜色、跨arena行状态、动态扩大容量、持久化、网络同步或历史审计。它是后续 `bounded_transaction_family_plan` 的单一二值基础，而不是一般状态管理系统。
