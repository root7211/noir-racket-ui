# Modal Focus Visual Plan v1 ABI

**状态：** 已实现，并通过真实 X11/Vulkan 输入与截图验证。
**Schema：** `noir-modal-focus-visual-plan-v1@1`。
**作者：** Manus AI。

## 1. 目的与边界

`modal_focus_visual_plan v1` 是 `modal_focus_subgraph v1` 的纯视觉伴随产物。它把每个**编译期固定的 modal Tab 目标**lower 为一枚独立、预分配的圆角 outline quad，并冻结其屏幕几何、SDF 参数、源实例反向见证和局部 tile 范围。运行时既不测量控件矩形，也不搜索可聚焦组件，更不分配新的 GPU 实例；它只能把已知 ring 的 alpha 从 `0` 切换为 `1`，或反向切换。[1] [2]

该 ABI 的作用不是创建通用的无障碍焦点系统，而是在 Noir 的受限、静态 modal 模型中，让键盘状态转换也具备明确、可验证且没有运行时布局工作的视觉结果。它只接受已经由 `overlay_state_plan v1` 管理为二元可见性的 overlay，以及已经由 `modal_focus_subgraph v1` 证明为有限 Tab 环的 event slot 集合。[1] [3]

| 性质 | v1 合同 |
|---|---|
| 可视对象 | 每个已批准的 modal Tab event 恰有一枚 ring quad。 |
| 运行时选择 | `Event Map slot → ring buffer slot` 是启动期构造的固定数组；热路径没有 ID 查找。 |
| 外扩几何 | 固定 `3 px` halo；环的 `x/y` 比 target 各小 `3 px`，宽高各大 `6 px`。 |
| SDF 外观 | `radius = min(12 px, min(width,height)/2)`；`thickness = 2 px`；导数驱动的最小 `0.5 px` 抗锯齿。 |
| 颜色 | 固定蓝色 `(0.36, 0.72, 1.0, 1.0)`；可变分量仅为实例颜色的 alpha lane。 |
| GPU 写入 | 打开写 1 个 `f32` alpha；每次 Tab/Shift+Tab 写旧、新华两个 `f32` alpha；关闭把全部预分配 ring 清零。 |
| 渲染顺序 | `root → shadows → static surfaces → focus rings → glyphs`。 |
| 局部重绘 | ring 的 `tile_ids` 必须与其 modal subgraph、overlay 和源 event release tile mask 完全相同。 |

> **定义。** “源实例反向见证”是 `source_instance_offset`：它必须是非根、44-byte 对齐的 `QuadInstance` 地址，并且必须精确等于同一 `focus_event_slot` 的 `Event Map.instance_offset`。它用于证明 ring 不是运行时重新定位或伪造的覆盖层。[1] [2]

## 2. 编译期lowering

用户不单独声明 ring。它由 `material-overlay-state` 中既有的 `#:modal-focus` 字面目标序列派生。例如，`deployment-confirm`、`deployment-dismiss` 和三个 menu item 在展开期已经形成确定的 Tab 环；focus visual pass 只消费该环及冻结后的 `Event Map`。因此 ring 的声明顺序、焦点顺序与运行时 buffer 顺序都无需再做任何排序或树遍历。[1]

```racket
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

每个目标产生一条 `c-modal-focus-visual-entry`。编译器只在 Event Map、layout offsets 和 task-local tiles 已经冻结以后运行这个 pass；因此不允许它改变 layout、glyph placement、packet worklist 或 action 的 GPU 写集。[1]

## 3. Scene JSON ABI

Scene 顶层有两个字段。只要 `#:modal-focus` lowering 成功，`modal_focus_visual_required` 必须是 `true`；普通没有 modal 焦点声明的 Scene 必须显式输出 `false`，保持现有 rounded/shadow 应用兼容。[1]

```json
{
  "modal_focus_visual_required": true,
  "modal_focus_visual_plan": {
    "abi_schema": "noir-modal-focus-visual-plan-v1",
    "abi_revision": 1,
    "entries": [
      {
        "id": "deployment-confirm$focus-ring",
        "focus_event_slot": 3,
        "source_instance_offset": 924,
        "x": 757.0,
        "y": 393.0,
        "width": 110.0,
        "height": 46.0,
        "radius_px": 12.0,
        "thickness_px": 2.0,
        "color": [0.36, 0.72, 1.0, 1.0],
        "tile_ids": [0]
      }
    ]
  }
}
```

| 字段 | 类型 | 启动期约束 |
|---|---:|---|
| `id` | string | 必须精确为 `${EventMap.node}$focus-ring`，且在计划内唯一。 |
| `focus_event_slot` | usize | 必须是 canonical Event Map 地址，且只能属于已批准的 modal Tab 子图。 |
| `source_instance_offset` | usize | 非零、`44` 对齐、位于已分配 QuadInstance 表中，并精确等于该 event 的实例地址。 |
| `x/y/width/height` | f32 | 必须有限且为正尺寸；必须由目标 event 的固定 `3 px` halo 算出。 |
| `radius_px` | f32 | `0 < radius ≤ min(width,height)/2`，并精确符合 v1 的 `min(12, …)` 配方。 |
| `thickness_px` | f32 | 精确为 `2.0`。 |
| `color` | `[f32;4]` | 精确为 v1 固定蓝色；运行时只改变独立 quad 的 alpha，而不改变该 metadata。 |
| `tile_ids` | `Vec<usize>` | 通过已编译 tile 表检查后，必须与 modal、overlay、event 的 local tile mask 完全一致。 |

`material-overlay-showcase` 的 v1 计划有 5 个条目，按固定 ring buffer 顺序如下。[1] [4]

| Ring buffer slot | Event slot | ID | 源 offset | 扩展后几何 `(x, y, w, h)` | Tile |
|---:|---:|---|---:|---|---:|
| 0 | 3 | `deployment-confirm$focus-ring` | 924 | `(757, 393, 110, 46)` | 0 |
| 1 | 2 | `deployment-dismiss$focus-ring` | 836 | `(641, 393, 110, 46)` | 0 |
| 2 | 4 | `menu-pin$target$focus-ring` | 1144 | `(933, 169, 214, 46)` | 0 |
| 3 | 5 | `menu-copy$target$focus-ring` | 1320 | `(933, 213, 214, 46)` | 0 |
| 4 | 6 | `menu-export$target$focus-ring` | 1496 | `(933, 257, 214, 46)` | 0 |

## 4. Rust 启动期 proof

Rust 在申请焦点 ring GPU buffer 和启动事件循环之前验证 ABI contract。若顶层 `required=true` 而 plan 被替换为 `false`，宿主必须拒绝 Scene；反之，普通 Scene 可保持 plan 为 `false`。[2]

接受 object 后，proof 依次验证 schema/revision、非空且精确的条目数、唯一 ID、canonical event slot、44-byte 对齐且反向匹配 Event Map 的 source offset、canonical ID 命名、有限几何、固定 halo/radius/thickness/color 配方、已批准的 modal 子图归属、overlay pairing，以及不扩大的 tile mask。最后，proof 构造长度等于 Event Map 的 `ring_for_event_slot: Vec<Option<usize>>`，并证明每个 Tab target 都有且仅有一个 ring buffer 地址。[2]

验证后的热路径结构不再携带可变 JSON 语义：

```rust
CompiledModalFocusVisualPlan {
    entries: Vec<CompiledModalFocusVisualEntry>,
    ring_for_event_slot: Vec<Option<usize>>,
}
```

这张 slot 表消除了运行时从 node ID、组件树或矩形反查 focus ring 的需求。[2]

## 5. GPU ABI 与渲染

每个 ring 使用一份独立 `QuadInstance`，其现有 ABI 仍为 44 bytes：`pos[2]`、`size[2]`、`color[4]` 与三个 glyph 字段。ring 的 glyph 字段固定为零；`color.a` 在 byte offset `28`，也是唯一允许修改的 lane。`GpuFocusRingMeta` 固定为 16 bytes：`[radius_px, thickness_px, width_px, height_px]`。[2]

启动期把已证明的像素矩形一次性转换为 NDC quad，创建独立 instance buffer、immutable metadata storage buffer、bind group 与 `host_focus_ring.wgsl` pipeline。outline fragment pass 用 outer rounded-box SDF 减去内缩 `thickness_px` 的 rounded-box SDF，借助 `fwidth` 和最小 `0.5 px` 过渡产生抗锯齿边缘。静态填充圆角 shader `host_quad.wgsl` 完全不被改变。[2] [5]

| 状态转换 | 固定 GPU alpha patch | 局部重绘 |
|---|---|---|
| Overlay open | 当前环 index `0` 的 ring alpha `0 → 1` | 关联 overlay tile mask，`NO_PACKETS`。 |
| `Tab` / `Shift+Tab` | 旧 ring `1 → 0`，新 ring `0 → 1` | 同一已证明 tile mask，`NO_PACKETS`。 |
| `Enter` close / `Escape` / scrim close | 所有预分配 ring alpha 归零 | 既有 overlay close tile mask。 |
| Replay reset | 所有 ring alpha 归零，modal `current_index=0` | 仅测试/回放重置；无动态地址发现。 |

## 6. v1 明确非目标

v1 不支持动态产生的 focus target、任意嵌套 modal、动态主题颜色、ring 宽度动画、运行时几何测量、窗口间焦点、平台可访问性桥接、ARIA 或 IME focus。它也不为普通 Focus Graph 字段创建通用 outline；这些能力只能在保留“编译期固定状态依赖、资源地址、几何和 GPU 写范围”原则的后续 ABI 中引入。

## References

[1] [Racket ABI、lowering 与Scene serializer](noir/ui/main.rkt)
[2] [Rust startup proof、GPU资源、outline pipeline与事件执行器](wgpu-verify/src/bin/noir_winit_host.rs)
[3] [Modal focus subgraph v1 ABI](MODAL_FOCUS_SUBGRAPH_ABI_V1.md)
[4] [Material overlay showcase fixture](examples/material-overlay-showcase.rkt)
[5] [Focus ring WGSL SDF outline shader](wgpu-verify/src/host_focus_ring.wgsl)
