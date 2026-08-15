# Noir `scrollbar_plan` v1 交付报告

**作者：** Manus AI  
**状态：** 已实现、已冻结为 v1、已在真实 X11/Vulkan 路径验证  
**目标：** 在不修改既有 `virtual_list_plan` 或 `row_activation_plan` 语义的前提下，提供第一个可见的、可拖动的长列表 scrollbar。

## 1. 交付结论

`scrollbar_plan` 已作为独立、版本化的 Scene artifact 接入 Noir。Racket 宏将受限 DSL 展开为 track 与 thumb 两个固定 QuadInstance，并在编译期输出 list binding、track rect、thumb instance offset、viewport domain、局部 tile IDs、no-packets worklist slot 与 physical ring rule。Rust 宿主在创建窗口后、进入事件循环前逐项反向 proof；真实 X11 pointer drag 只执行固定映射、row recycling、一个 thumb `pos.y` patch、既有 viewport renderer 与一个局部 no-packets tile 请求。[1] [2] [3]

> 这不是“滚动条组件在运行时驱动UI树”。它是一个固定输入适配器：pointer y 被投影到已经存在的 virtual-list viewport domain；所有几何、GPU 地址、worklist 与局部提交范围都早已由编译器给出。

| 层次 | v1 结果 |
|---|---|
| DSL | 新增 `(scrollbar #:id … #:for … #:x … #:y … #:width … #:height … #:thumb-height …)`；全部参数必须为静态字面量。 |
| 编译期节点 | track 与 `id$thumb` 均 materialize 为基础 QuadInstance，具有固定 layout/instance offsets。 |
| Scene ABI | 新增 `abi_contracts.scrollbar_plan` 与 `scrollbar_plans[]`，schema 为 `noir-scrollbar-plan-v1@1`。 |
| Host proof | 验证 list、compact direct-scroll资格、track/thumb layout、thumb address、viewport domain、tile scope、physical ring rule 与 no-packets slot。 |
| 热路径 | `pointer → clamp/map → compact scroll → thumb pos.y patch → scroll request + local tile request`。 |

## 2. 固定数据流

针对 `telemetry-registers` 的 10,000 行 fixture，编译器输出的 scrollbar artifact 为：track `12×84 + (588,106)`，thumb 高 `18`，最大 viewport 为 `9997`，thumb GPU instance offset 为 `572`，局部 tile 为 `[2]`，packet worklist 为空 `no-packets` slot `2`。其 logical-to-physical 行映射仍严格复用冻结规则 `logical-mod-physical-slots`。

| 输入/产物 | 固定值或固定规则 | 运行时是否重新求解 |
|---|---|---|
| Track / thumb geometry | `x=588, y=106, width=12, height=84, thumb=18` | 否 |
| Pointer→viewport | `round(clamp(pointer_y - track_y - 9, 0, 66) / 66 × 9997)` | 仅执行该有限算术表达式 |
| 逻辑→物理行 | `logical mod 4` | 否；直接执行固定映射 |
| Row GPU范围 | 3 个固定 row draw ranges、3 个 glyph subranges | 否 |
| Thumb GPU 写入 | `thumb_instance_offset + 4`，即 QuadInstance `pos.y` | 否；单个 f32 patch |
| Packet activity | worklist `2 = []` | 不执行 compute dispatch |
| 局部恢复 | compiler-selected tile `[2]` | 不生成或扩大 tile mask |

中段拖动到窗口 y=`148` 时，运行时 target 为 `4999`。实际行 ring 变为 `[3,0,1]`，仅进行了 36 个预先绑定 glyph ID patch；viewport renderer 提交了 3 个 quad ranges、6 个 quad instances、3 个 glyph subranges、27 个 glyph placements，且 worklist 保持 `no-packets`。这证明 scrollbar 没有把长列表退化为整表重建或完整 packet replay。

## 3. 严格准入和负向 proof

`compiler_scrollbar_plans` 为每项 artifact 检查 schema/revision、唯一 scrollbar/list binding、compact data-register direct-scroll资格、`max_viewport = logical_capacity - visible_rows`、track/thumb与 Layout Plan 的精确几何对应、instance offset、局部 tile精确交集以及 empty worklist。任一不匹配都会在事件循环前终止启动。

| 篡改项 | 预期与实际结果 |
|---|---|
| 将 `tile_ids: [2]` 扩大为 `[1,2]` | 启动拒绝：`scrollbar telemetry-scrollbar has widened or incorrect compiler tile scope`。 |
| 将 artifact schema 改为 `noir-scrollbar-plan-v9` | 启动拒绝：`scrollbar telemetry-scrollbar has unsupported ABI noir-scrollbar-plan-v9@1`。 |
| 顶层 list ABI revision 篡改 | 既有 ABI freeze oracle 继续拒绝。 |
| row activation artifact schema 篡改 | 既有 Row Activation proof 继续拒绝。 |

## 4. 真实验证

本交付使用 Racket 实际构建器输出的 Scene、Rust release `noir_winit_host`、Xvfb X11 event loop 和 `WGPU_BACKEND=vulkan`。真实 drag 使用窗口焦点后的 XTEST mouse move / press / move / release，而不是调用内部函数或伪造 Host 状态。

| 验证 | 状态 | 关键证据 |
|---|---|---|
| Racket 全量回归 | 通过 | 既有DSL fixture可在Scene新增scrollbar contract后稳定展开。 |
| Rust `cargo check` / release | 通过 | Rust 1.75兼容Host含新ABI和drag执行器。 |
| Scene启动期proof | 通过 | `compiler scrollbar … tiles=[2] worklist=2`。 |
| 真实X11中段拖动 | 通过 | y=148 → viewport=4999。 |
| 物理ring复用 | 通过 | `[3,0,1]`，仍为4 physical slots。 |
| 局部glyph / draw提交 | 通过 | 3 ranges / 6 quads / 3 subranges / 27 glyph placements。 |
| no-packets worklist | 通过 | 直接记录 `worklist=no-packets`。 |
| tile / schema篡改 | 按预期拒绝 | 启动期proof拒绝扩大范围与不同版本。 |
| 既有ABI freeze回归 | 通过 | 新独立contract没有破坏virtual-list/row activation v1。 |

可复现实验入口是 `tools/verify_scrollbar_plan.sh`。它会重建 Scene，运行真实X11 drag，再产生 widened-tile 与 schema-drift 场景并断言它们失败。[4]

## 5. 下一阶段边界

下一项应实现 `list_navigation_plan` v1，用于 PageUp、PageDown、Home 与 End。它应复用相同的 `list_id`、`max_viewport`、physical ring、thumb sync 和 `RenderRequest::scroll` 路径；不可把 navigation 变成逐行迭代、动态布局或文本重新 shaping。建议先实现四个静态 transition kind，再让它们调用相同的 `scroll_compact_list_to`，以确保 scrollbar、wheel 和键盘大步导航始终保持同一固定thumb / viewport状态。

## References

[1]: [scrollbar_plan v1正式接口规范](SCROLLBAR_PLAN_ABI_V1.md)  
[2]: [Racket DSL、静态布局与Scene lowering](noir/ui/main.rkt)  
[3]: [Rust ABI proof、pointer drag与wgpu局部渲染](wgpu-verify/src/bin/noir_winit_host.rs)  
[4]: [真实X11与篡改负向回归脚本](tools/verify_scrollbar_plan.sh)  
[5]: [冻结的virtual-list与row activation ABI](VIRTUAL_LIST_ROW_ACTIVATION_ABI_V1.md)
