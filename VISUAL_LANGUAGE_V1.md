# Noir 编译期桌面视觉语言 v1

**状态：实施规范**
**目标：让视觉层级、状态语义和桌面空间结构成为编译期产物，而非运行时样式解释。**

## 1. 视觉语言的边界

Noir视觉语言不是CSS主题系统，也不是一套由宿主在运行时查询的皮肤对象。`theme`、`visual-preset`、`surface`、`divider`、`status-indicator`和组件variant必须在Racket宏展开期lower为固定RGBA、固定px几何、固定quad/glyph placement、clip范围和tile引用。

> 视觉规则必须能被编译器计算、被Scene记录、被Rust宿主拒绝越界产物；不能以“美观”为名重新引入运行时布局或动态样式解析。

v1只支持离散surface elevation与硬边/低alpha层叠，不支持任意blur shadow、backdrop filter、透明毛玻璃、运行时颜色混合或任意responsive reflow。

## 2. 语义token

每个应用主题必须提供下列语义色彩；颜色名称而非硬编码RGBA描述用途。宏展开后的Scene仍只持有最终RGBA。

| token | 用途 | 约束 |
|---|---|---|
| `canvas` | 窗口底层背景 | 最高对比留白区域 |
| `canvas-quiet` | 非交互余白/导航区域 | 与canvas可区分但低对比 |
| `surface` | 常规内容层 | 表格、详情、表头的基础层 |
| `surface-raised` | 提升内容层 | 卡片、选中详情、重点frame |
| `surface-overlay` | 覆盖层 | 固定dialog/menu预留层 |
| `border-subtle` / `border-strong` | 层级和焦点边界 | 不作为大面积填充 |
| `text-primary` / `text-muted` / `text-inverse` | 字体角色 | 静态chrome使用比例face；密集数据使用legacy glyph域 |
| `accent` / `accent-muted` | 主操作与selected outline | selected不得整行高饱和填充 |
| `success` / `warning` / `danger` / `info` | 状态语义 | 动态行用tint或indicator，不用整行纯色覆盖 |

`space`必须至少定义`xs`、`sm`、`md`、`lg`、`xl`、`page`；`type`定义`caption`、`body`、`label`、`title`、`display`；`radius`定义`control`、`card`、`panel`、`overlay`。`elevation`定义离散`flat=0`、`border=1`、`raised=2`、`overlay=3`。

## 3. 桌面空间与密度

`visual-preset`只允许静态预设。

| preset | host窗口 | content margin | list row | 应用 |
|---|---:|---:|---:|---|
| `bench` | 640×360 | 12 px | 28 px | 微基准与ABI fixture |
| `desktop-compact` | 1024×720 | 24 px | 30 px | 设置、单表格 |
| `desktop-wide` | 1280×720 | 32 px | 28 px | 日志浏览器、实时监控 |

一份Scene只对应一个preset。窗口跨越preset不触发运行时reflow，而是要求重新加载相应已编译Scene。`app-shell`在desktop预设中生成明确的content frame；两个应用v1使用`desktop-wide`。

## 4. Surface与elevation

`surface`接受静态`#:elevation`。每个等级的lowering均为固定quad数量和固定tile范围。

| elevation | 视觉组成 | maximum extra quads |
|---|---|---:|
| `flat` | fill | 0 |
| `border` | fill + 1px底部分隔线 | 1 |
| `raised` | raised fill + 1px底部分隔线 | 1 |
| `overlay` | overlay fill + 1px强分隔线 | 1 |

v1的corner visual以既有离散radius token和层叠rect近似表达；若后续增加rounded-rect shader specialization，必须新建版本化GPU实例ABI，不得隐式改变现有44-byte `QuadInstance`。

## 5. 组件规则

| 组件 | 视觉语义 | 编译期规则 |
|---|---|---|
| `app-shell` | canvas + desktop content frame | preset决定固定window与padding；不运行时resize |
| `toolbar` | raised标题bar | page-2 title，`text-primary`，底部divider |
| `table-header` | 低对比元数据带 | page-2 label，`text-muted`，header divider |
| `surface` | 分层frame | 固定elevation、border与clip |
| `divider` | section/column分隔 | 1px固定quad；无独立状态 |
| `status-indicator` | 行/详情状态 | 4px indicator或低alpha tint；语义颜色固定到对应状态slot |
| `status-pill` | 动作或状态摘要 | 小型surface，不作为整宽高饱和操作条 |
| `detail-panel` | 选中对象上下文 | raised surface、顶部divider、固定dynamic glyph范围 |

## 6. 迁移规则

日志浏览器与实时监控表格的基础list ABI保持不变。视觉层只能包裹或引用既有list ID、row tile、glyph range和detail tile。selected-row采用accent outline/raised detail；监控WARN/ERROR采用固定左边indicator与低alpha行tint，不能改动data-register容量、row glyph slot、event map或worklist地址。

## 7. 编译产物与验证

Scene必须持有版本化`visual_language_plan`，包括schema、revision、preset、canvas width、height与margin。Rust启动期同时验证ABI合同、封闭preset尺寸和全部layout的canvas containment；surface/divider本身已经lower为普通固定quad，因此不需要运行时组件解释。每次修改必须运行：Racket宏测试、Scene proof、真实X11/Vulkan截图、日志浏览器和监控表格交互回归。
