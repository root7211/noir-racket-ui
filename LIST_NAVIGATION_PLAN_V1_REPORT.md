# Noir `list_navigation_plan` v1 交付报告

**作者：** Manus AI  
**状态：** 已实现、已通过真实 X11/Vulkan 验证  
**目标：** 将 PageUp、PageDown、Home、End 编译为固定 viewport transition，复用已冻结的 virtual-list 与 scrollbar 路径，而不引入运行时遍历、布局或渲染策略旁路。

## 1. 交付结论

`list_navigation_plan` 已作为第四个独立版本化 artifact 加入 Scene ABI。Racket DSL 只声明 list 与 scrollbar 的静态关系；编译器固定四键 transition、page step、max viewport、no-packets worklist 和局部 tile 范围。Rust 在事件循环前证明其与 virtual-list / scrollbar ABI 精确一致；实际键盘事件只选择一项 transition，随后复用 compact row recycling、thumb sync 和既有局部 renderer。[1] [2] [3]

> 运行期不以“多次 ArrowDown”模拟 PageDown。它只执行一次编译器固定的 `min(max_viewport, viewport + page_step)` transition。

| Artifact | v1 结果 |
|---|---|
| ABI schema | `noir-list-navigation-plan-v1@1` |
| DSL | `(list-navigation #:id … #:for virtual-list-id #:scrollbar scrollbar-id)` |
| 固定 transitions | `page-up`、`page-down`、`home`、`end`，顺序和kind均受proof约束 |
| 绑定 | 一个 compact data-register list 与同一 list 的 scrollbar plan |
| 渲染 | 既有 `RenderRequest::scroll` + scrollbar 的 local `no-packets` tile |
| 禁止项 | 逐行循环、运行期list/scrollbar检索、layout/shaping、packet worklist构造 |

## 2. 编译产物与执行定律

10,000 行 `telemetry-registers` fixture 产生以下固定计划：`page_step=3`（可见行数）、`max_viewport=9997`、`tile_ids=[2]`、worklist slot `2=no-packets`，并保持 `logical-mod-physical-slots` 的四槽ring规则。

| Key | 编译期 kind | 目标 viewport |
|---|---|---|
| PageUp | `subtract-step` | `max(0, v - 3)` |
| PageDown | `add-step-clamp` | `min(9997, v + 3)` |
| Home | `set-zero` | `0` |
| End | `set-max` | `9997` |

所有非边界 transition 经过同一路径：

```text
X11 KeyboardInput
→ CompiledListNavigationPlan
→ target viewport
→ scroll_compact_list_to
→ apply_compact_register_scroll
→ fixed scrollbar thumb pos.y patch
→ viewport RenderRequest + local no-packets tile request
```

当 target 等于当前 viewport，宿主仅记录 `boundary`；不会写GPU、不会构造worklist、不会请求重绘。

## 3. 启动期 proof

Rust `compiler_list_navigation_plans` 会在窗口创建后、事件循环前验证：顶层contract与artifact schema/revision、plan/list唯一绑定、绑定scrollbar属于同一list、compact direct-scroll资格、`page_step == visible_rows`、`max_viewport == logical_capacity - visible_rows`、四条transition的精确顺序/种类、tile IDs与scrollbar计划相等、空packet worklist和physical ring rule。

| 篡改 | 实际结果 |
|---|---|
| 将 `page-up` kind 从 `subtract-step` 改为 `add-step-clamp` | 启动拒绝：transition table is not canonical。 |
| 将 navigation tile IDs 从 `[2]` 扩大为 `[1,2]` | 启动拒绝：disagrees with bound scrollbar tile scope。 |
| 篡改顶层virtual-list revision或row activation schema | 冻结ABI回归继续拒绝。 |
| 篡改scrollbar tile/schema | scrollbar v1回归继续拒绝。 |

## 4. 真实 X11/Vulkan 验证

验证使用 Racket 真实导出的 Scene、release Rust host、Xvfb、真实 `xdotool` 键盘输入和 Vulkan llvmpipe 后端。向真实窗口依次发送 `End → PageUp → PageDown → Home`，得到确定性的 viewport 闭环。

| 输入 | From | To | 关键证据 |
|---|---:|---:|---|
| End | 0 | 9997 | 一次 transition 跳至最后合法viewport，thumb同步至底部。 |
| PageUp | 9997 | 9994 | 一次三行步长转换，无逐行迭代。 |
| PageDown | 9994 | 9997 | clamp回最大viewport。 |
| Home | 9997 | 0 | 一次 transition 回到起点，thumb同步至顶部。 |

四个动作均保留 4 个 physical slots、`no-packets` worklist 和现有局部提交。其列表绘制每次都只提交 3 个 row draw ranges、6 个 quad instances、3 个 glyph subranges 与 27 个 glyph placements；没有扩展为全表重建。

## 5. 可复现入口和冻结决定

`tools/verify_list_navigation_plan.sh` 会重建 fixture、启动真实X11、发送四键、断言viewport/ring/thumb/local worklist，再构造transition与tile篡改Scene并验证启动拒绝。[4]

到此，长列表交互层的关键输入路径已经完整：wheel、ArrowUp/ArrowDown、row release/Enter、scrollbar drag 与 PageUp/PageDown/Home/End 都收束到已冻结 ABI 和相同的 compact viewport executor。下一步不应再扩大底层 ABI；应开始用此接口构建**日志浏览器**与**实时监控表格**两个用户可见示例。

## References

[1]: [List Navigation Plan ABI v1](LIST_NAVIGATION_PLAN_ABI_V1.md)  
[2]: [Racket DSL and compiler lowering](noir/ui/main.rkt)  
[3]: [Rust proof and X11 keyboard executor](wgpu-verify/src/bin/noir_winit_host.rs)  
[4]: [Real X11 and tamper-proof regression](tools/verify_list_navigation_plan.sh)  
[5]: [Scrollbar Plan ABI v1](SCROLLBAR_PLAN_ABI_V1.md)
