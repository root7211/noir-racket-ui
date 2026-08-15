# Log Browser：冻结列表ABI上的首个完整用户示例

**作者：Manus AI**  
**状态：已实现并通过真实 X11/Vulkan 回归**

## 摘要

`examples/log-browser.rkt` 是 Noir 在冻结列表交互层上的第一个完整用户可见示例。它并未为应用层引入新的布局遍历、可变文本系统或渲染旁路，而是把一个固定容量的日志浏览器降低为既有虚拟列表、数据注册表、scrollbar、键盘导航、行激活和局部渲染请求的组合。

示例声明 `system-log` 为 **10,000 条逻辑记录**、**4 个物理GPU槽位**、**3 条可见行**、**28 px 行高**的紧凑数据注册表。每条固定宽度记录表达为 `LEVEL | TIME | SOURCE | MESSAGE` 四列。日志级别受限于 `INFO`、`WARN`、`ERROR` 和 `DEBUG`；宿主只把这个有限枚举映射到编译器导出的四个固定颜色，不搜索节点，也不构造临时样式对象。

| 能力 | 静态工件 | 运行时最短路径 |
|---|---|---|
| 10,000 条日志 | `virtual_list_plan` v1 | 4-slot row ring 与可见行glyph子范围 |
| 行选择 | `list_interaction_plan` v1 | 一个物理row颜色地址、selection局部请求 |
| Tail append | `log_browser_plan` v1 | 3条编译期固定tail更新；离屏时零glyph GPU写入 |
| 滚动到底部 | `list_navigation_plan` v1 | `End → viewport=9997 → ring recycle` |
| 详情面板 | `log_browser_plan` v1 | 26个已tile覆盖的glyph ID地址与tile 0 |
| Enter / release | `row_activation_plan` v1 | `Action Slot 0 → coalesced-activate-append-tail → no-packets` |

## `log_browser_plan` v1

日志浏览器是**独立应用层ABI**。顶层Scene contract要求 `noir-log-browser-plan-v1@1`，但它只读取并交叉验证已冻结的列表和交互工件；不会改变 `virtual_list_plan`、`row_activation_plan`、`scrollbar_plan` 或 `list_navigation_plan` 的字段语义。

计划固定了列表ID、tail append batch、追加记录索引和值、详情glyph偏移、详情tile、物理row颜色偏移、level颜色表与 `no-packets` worklist。日志正文不能从命令行或鼠标事件直接写入GPU：`--inject-log-append system-log-browser` 也只会执行编译器已导出的三条tail记录。

> 详情文本可能在视觉上接近裁剪边界。因此编译器只导出其局部tile packet subrange真正覆盖的 **26** 个glyph cell；宿主启动期反向proof会拒绝任何扩张至被裁剪placement的artifact。

## 验收工作流

回归入口是：

```bash
./tools/verify_log_browser.sh
```

脚本使用真实X11窗口和Vulkan后端，依次执行：tail append、真实 `End`、真实鼠标释放选择第二条tail记录（`ERROR`）、真实 `Enter`。它也篡改 `log_browser_plan` schema，确认宿主在窗口初始化前拒绝漂移工件。

| 真实日志证据 | 已验证结果 |
|---|---|
| Tail append | `updates=3 visible=0 arena-only=3 gpu-glyph-writes=0 render-request=false` |
| End | `0 → 9997`，row tiles `[1, 2, 3]`，仍为4物理槽位 |
| ERROR row | 逻辑行 `9998`、物理槽位 `2`、固定颜色偏移 `412` |
| 详情 | `glyph-writes=26`、tile mask `0x1`、worklist `2` |
| Activation | `coalesced-activate-append-tail`，成员worklist为空且为 `no-packets` |
| 局部绘制 | 详情只提交 tile 0 的 `placements=[143..169)` 子范围 |

## 运行与限制

先以Rust 1.87与wgpu 30构建release宿主，再导出和运行示例：

```bash
NOIR_ENTRY_MODULE=examples/log-browser.rkt PLTCOLLECTS="$PWD:" \
  racket tools/export-dashboard.rkt out/log-browser.scene.json
./tools/verify_log_browser.sh
```

本示例的append是故意固定的编译期tail batch，用于验证应用层可消费既有 `data-update-batch` 语义。它不是任意外部日志流接入；后者需要一个新的、明确版本化的有界ingress ABI，而不能绕过当前固定文本、GPU写入范围和worklist证明。

## 结论

日志浏览器证明了 Noir 的冻结长列表交互层已能承载完整用户工作流：**离屏日志追加、End、review、选择、详情和激活**。每一步仍然只消费已编译的数据流，而不是回退为动态widget tree或通用UI运行时。

下一项应用层工作应是实时监控表格：复用相同的列表ABI，用可见性分流处理周期性指标更新，并将现有用户示例从单一日志工作流扩展为两个不同的数据密集型桌面场景。
