# `modal_focus_subgraph v1` 交付报告

**日期：** 2026-08-17
**作者：** Manus AI
**状态：** 已完成实现、真实 X11/Vulkan 验证、回归验证与开源发布准备。

## 摘要

本次实现将可开关 Material dialog/menu 的键盘焦点语义从运行时推断转换为 Scene 中的显式、有限、可证明子图。`deployment-overlay` 的打开、Tab、Shift+Tab、Enter、Escape 和 scrim pointer dismiss 都只消耗预先分配的 state slot、event slot、alpha patch 地址和 tile mask；宿主不会遍历组件树、计算下一个可焦点节点或重新布局。[1] [2]

真实 X11/Vulkan 验证证明：打开 overlay 后，焦点入口固定在 event slot 3；五次 Tab 走完 `3 → 2 → 4 → 5 → 6 → 3` 环；一次 Shift+Tab 走 `3 → 6`；Enter 激活当前固定 menu target 并关闭 overlay；点击原背景 open 区域被 scrim 的关闭 event 接管，背景 open action 没有再次分发。[3]

## 实现结构

| 层 | 交付物 | 固定内容 | 运行时工作 |
|---|---|---|---|
| Racket 宏 | `material-overlay-state #:modal-focus` | 入口、恢复event、声明顺序Tab环、close event集与tile | 无解析或图搜索。 |
| Scene ABI | `modal_focus_subgraph_plan` + `modal_focus_subgraph_required` | schema、state slot、event slot、正反边、tile ID | JSON反序列化。 |
| Rust proof | `compiler_modal_focus_subgraph_plan` | 反向校验overlay state、actions、Tab环、scrim允许集、tile | 压缩为索引表。 |
| 键盘执行器 | `modal_focus_tab`、`modal_focus_activate` | 当前环索引、next/previous表 | 常数时间数组索引。 |
| overlay集成 | `apply_overlay_state` | open入口、close恢复上下文 | 调用关联的alpha patch和局部重绘。 |

## 实际状态机

`deployment-overlay` 的编译产物含一个状态 `overlay-visible`（slot 0）。open action `overlay-open` 写 `1`；`overlay-confirm`、`overlay-dismiss`、`overlay-pin`、`overlay-copy` 与 `overlay-export` 写 `0`。modal Tab targets 是 `[3, 2, 4, 5, 6]`；scrim close event slot 1 只属于 pointer-allowed 集合而不属于键盘Tab环。[1] [2]

> 因此，打开modal不会让背景Button、列表、普通Focus Graph或Keyboard Command Map参与Tab/Enter分发。只有overlay的固定子图可以消耗这些按键。

## 验证结果

| 验收项 | 结果 | 证据 |
|---|---|---|
| Racket语言回归 | 通过 | `Noir Cost Model language checks passed`。 |
| Scene结构oracle | 通过 | `MODAL_FOCUS_SUBGRAPH_V1_ORACLE: PASS`。 |
| Rust 1.87 / wgpu 30 | release构建通过 | Scene wire、proof和键盘路径均通过类型检查。 |
| 真实GPU启动 | 通过 | `compiler modal focus: v1 entries=1 fixed-tab-targets=5 background-isolated no-packets`。 |
| Tab/Shift+Tab环 | 通过 | 真实X11日志确认正向wrap与逆向边。 |
| Enter | 通过 | 当前event slot的固定action执行，随后overlay关闭。 |
| Escape | 通过 | modal优先关闭，恢复slot 0的预声明上下文。 |
| 背景pointer隔离 | 通过 | 打开overlay后背景open坐标命中scrim dismiss；open dispatch总数保持一次。 |
| 篡改拒绝 | 通过 | edge、allowed、tile、disable 均在事件循环前被拒绝。 |

## 篡改拒绝

| 攻击 | 篡改内容 | 启动期拒绝原因 |
|---|---|---|
| `edge` | 把第一条正向Tab边改为非canonical目标 | `noncanonical Tab ring edge`。 |
| `allowed` | 将背景open slot 0加入modal允许集合 | `allowed event set must equal` 固定close/scrim集合。 |
| `tile` | 将唯一tile 0替换为tile 1 | `tile ID 1 exceeds compiled tile table`。 |
| `disable` | 将计划替换为`false` | `modal_focus_subgraph_required` 禁止静默关闭。 |

## 已知边界与后续方向

v1 语义正确但尚未绘制独立的键盘焦点ring；真实X11日志和固定环状态已验证键盘隔离与激活行为。下一步可以在不改变子图ABI的前提下实现 `modal_focus_visual_plan v1`：为每个Tab target预分配focus ring quad，并只patch当前环索引对应的alpha。随后，应将navigation、可开关overlay、10,000行虚拟列表和焦点子图组合为单一 Material observability workbench，以检验Noir在连续使用场景下的组件组合能力。

## References

[1] [Modal focus ABI](MODAL_FOCUS_SUBGRAPH_ABI_V1.md)
[2] [Racket implementation and fixture](noir/ui/main.rkt)
[3] [Real X11/Vulkan regression](tools/verify_modal_focus_subgraph_v1.sh)
