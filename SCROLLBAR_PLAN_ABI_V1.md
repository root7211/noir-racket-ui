# Noir Scrollbar Plan ABI v1

**状态：** Draft implementation contract  
**规范标识：** `noir-scrollbar-plan-v1`，revision `1`  
**依赖：** `noir-virtual-list-plan-v1` revision `1`；该依赖是只读的。

> `scrollbar_plan` 不是对 virtual list 的第二份布局计划。它是一个独立的输入适配器：以固定 track/thumb 几何把 pointer y 映射为已经存在的 list viewport target，然后复用冻结的 compact scroll executor 与 viewport-only RenderRequest。

## 1. Scene ABI

每一个 `scrollbar_plans[]` 元素必须携带 `abi_schema: "noir-scrollbar-plan-v1"` 与 `abi_revision: 1`，顶层 `abi_contracts.scrollbar_plan` 必须声明同一 pair。

| 字段 | 类型 | v1 固定语义 |
|---|---|---|
| `id` | string | scrollbar 的唯一 compiler ID。 |
| `list_id` | string | 精确引用一个已冻结 `virtual_list_plan.id`。 |
| `track_id` / `thumb_id` | string | 对应固定 Layout Plan entry。 |
| `track_instance_offset` | unsigned integer | track QuadInstance 基地址，仅作启动期交叉 proof。 |
| `thumb_instance_offset` | unsigned integer | thumb QuadInstance 基地址；拖动期唯一允许的几何写入目标。 |
| `track` | `{x,y,width,height}` | 固定屏幕像素 rect。 |
| `thumb_height` | positive integer | 固定 thumb 高度，且不大于 track height。 |
| `max_viewport` | unsigned integer | `logical_capacity - visible_rows`。 |
| `packet_worklist_index` | unsigned integer | v1 精确为 no-packets slot `2`。 |
| `physical_slot_rule` | string | 精确为 `logical-mod-physical-slots`。 |

## 2. Pointer 映射定律

令 `T = track.height - thumb_height`，`M = max_viewport`，pointer 的屏幕 y 为 `p`。运行期可执行的唯一连续映射是：

```text
clamped_thumb_y = clamp(p - track.y - thumb_height / 2, 0, T)
target_viewport = round(clamped_thumb_y / T × M)
```

随后 host 仅做：

```text
target_viewport
→ apply_compact_register_scroll(list_index, target_viewport)
→ patch thumb pos.y at thumb_instance_offset + 4
→ RenderRequest::scroll(list_index, target_viewport)
```

`T`、`M`、track rect、thumb height、list index、physical ring rule、GPU patch offset 和 packet slot 都在启动期或编译期确定。输入期不遍历节点、不测量布局、不构造 packet worklist、不申请 GPU资源、不生成新的 draw/glyph range。

## 3. v1 约束

| 约束 | 原因 |
|---|---|
| 一个 scrollbar 只能引用一个 virtual list | 避免运行期 list routing。 |
| 一个 virtual list 在 v1 中最多一个 scrollbar | 防止多个thumb对同一viewport状态竞争。 |
| track/thumb layout entry 的 instance offset 必须与计划精确一致 | 将拖动写入限制在一个预证明的 `pos.y` f32。 |
| `track.width == thumb.width` 且 `0 < thumb_height ≤ track.height` | 防止 host 求解thumb几何。 |
| `max_viewport == logical_capacity - visible_rows > 0` | 禁止无滚动域的虚假 scrollbar。 |
| worklist 精确为 no-packets | thumb与row recycling都不需要 packet activity compute。 |
| render 使用既有 `RenderRequest::scroll` | 保持行 quad/glyph subrange提交范围不变。 |

## 4. DSL v1

```racket
(scrollbar #:id telemetry-scrollbar
           #:for telemetry-registers
           #:x 554 #:y 0
           #:width 12 #:height 84
           #:thumb-height 18)
```

所有参数必须为字面量；`#:for` 必须引用同一 static root 内的 virtual list。编译器将 materialize track 与 `id$thumb` 两个基础 QuadInstance，并输出一个独立 `scrollbar_plan`。后续 PageUp/PageDown/Home/End 应引用同一 list scroll domain，但不得修改本 ABI 的字段语义。

## References

[1]: [Frozen virtual list and row activation ABI v1](VIRTUAL_LIST_ROW_ACTIVATION_ABI_V1.md)  
[2]: [Racket DSL / layout / Scene lowering](noir/ui/main.rkt)  
[3]: [Rust wgpu host scroll executor](wgpu-verify/src/bin/noir_winit_host.rs)
