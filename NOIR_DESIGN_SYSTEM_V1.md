# Noir Design System v1：编译期桌面视觉系统

**作者：Manus AI**  
**状态：设计冻结候选；尚未改变既有virtual-list ABI。**

## 1. 目标

Noir Design System v1 的目标不是模仿保留式GUI框架的主题对象或运行时组件树，而是让**视觉质量本身成为可编译的输入**。应用开发者声明颜色、字号、间距、圆角、elevation、字体资源和组件组合；Racket在构建期将它们lower为固定RGBA、NDC几何、atlas UV、glyph placement、quad instance、damage tile和worklist引用。运行时不得查询theme、测量字体、分配组件、重排布局或决定GPU写入范围。

> EUI-NEO的经验是：设计token、真实字体、图标和默认组件样式必须是框架的一等能力。Noir的差异是：这些能力必须在**编译期消失为已证明的渲染数据**。

## 2. 非目标

Design System v1 不引入任意运行时CSS、动态字体fallback、运行时unicode shaping、自动responsive reflow、运行时阴影模糊、组件对象树或全局dirty-rect遍历。每一种可见状态与资源必须有静态上界、固定slot或显式版本化plan。

## 3. 视觉token ABI

### 3.1 声明形式

```racket
(theme noir-desktop
  (color canvas #0E1117 surface #171B24 surface-raised #1F2633
         text #F4F7FB muted #9AA6B7 accent #4C8DFF
         success #47C98B warning #F2B84B danger #F06A6A)
  (space 4 8 12 16 24 32 48)
  (radius 6 10 14 18)
  (type caption 13 body 15 label 16 title 28 display 36)
  (elevation flat border raised overlay))
```

`theme` 只允许模块字面量。宏在expand阶段建立符号表，所有token引用都被替换为常量；最终Scene不得持有可变theme map。

### 3.2 编译产物

| token类别 | 编译产物 | 运行时工作 |
|---|---|---|
| `color` | 固定RGBA、hover/selected预混色、semantic palette表 | 按固定instance字节offset写既有颜色字段 |
| `space` | 固定px/NDC几何与layout常数 | 无 |
| `radius` | fixed-radius shader variant ID与quad instance字段 | 无 |
| `type` | `font-face-id`、字号、line-box、glyph capacity与placement | 仅写预留glyph cell内容/颜色 |
| `elevation` | 预展开border与离散shadow quad集合 | 按组件的已证明tile重绘 |

## 4. 字体与图标：构建期资源编译

### 4.1 `noir-fontc`

`noir-fontc` 是构建期工具，而非宿主运行时服务。输入为字体文件、字号集合、语言coverage、项目字典和icon子集；输出为：

1. 灰度或MSDF atlas page；
2. 每个glyph的atlas rect、advance、bearing、baseline与line-height；
3. 字符/图标到glyph ID的静态索引；
4. font license manifest；
5. 可由Racket宏读取的`font-manifest.json`。

Racket在编译时拒绝不在coverage里的文本；可选的`(font-dictionary ...)`允许日志message、标题和业务术语定义有限宇集。应用对可预测字典使用静态glyph placement，对固定容量动态字段使用固定glyph cell + 预定义字符编码表。

### 4.2 渐进层级

| 版本 | 能力 | 对Noir性能模型的影响 |
|---|---|---|
| v1 | ASCII、数字、标点、icon子集、Noto Sans/JetBrains Mono预烘焙 | 零运行时shaping |
| v1.1 | 中文项目字典、静态CJK字符串 | atlas增长，但GPU写范围仍固定 |
| v2 | 受限动态文本字典与truncation table | 固定字符cell上界，不允许任意字符串扩张 |
| 非当前范围 | 任意unicode fallback、Harfbuzz运行时shaping | 会破坏确定性；暂不引入 |

## 5. 编译期内联组件

组件是宏，不是运行时widget。每个组件展开为基础rect、rounded rect、glyph run、clip、事件map与局部tile。

| 宏 | 编译期展开内容 | 固定运行时路径 |
|---|---|---|
| `app-shell` | canvas、导航rail、content frame、surface层级 | 仅用户声明的热点tile重绘 |
| `surface` | fill、border、radius与有限elevation quad | 预证明quad instance patch |
| `card` | raised surface、padding、clip与标题glyph run | 预证明component tile |
| `toolbar` | 标题、subtitle、icon glyph、button hit map | Action Slot + fixed color patch |
| `table-header` | 固定列标题、separator、sort icon slots | 固定glyph/color patch |
| `status-pill` | 小radius surface、semantic颜色、glyph run | 固定row subrange |
| `detail-panel` | surface、label/value glyph cells、fixed detail tile | no-packets direct glyph draw |

## 6. Surface、边框与elevation

Noir v1使用离散、可计量的elevation，而非任意昂贵blur。`flat`只生成fill；`border`生成fill + 1px边；`raised`生成fill + border + 两个低alpha静态shadow quad；`overlay`最多增加四个shadow quad。每个style的quad数和tile范围在构建期明确，因此不会引入依赖backdrop的全屏damage扩张。

Rounded rect第一版使用有限radius bucket `{6, 10, 14, 18}`；每一个bucket是shader specialization或instance字段的固定值。无任意运行时radius，不做动态几何tessellation。

## 7. Desktop art direction

用户示例不再复用640×360的benchmark canvas。Design System v1定义以下静态target：

| preset | 画布 | 外边距 | 典型用途 |
|---|---:|---:|---|
| `bench` | 640×360 | 12 | ABI与局部更新oracle |
| `desktop-compact` | 1024×720 | 24 | 表格、日志、设置 |
| `desktop-wide` | 1280×800 | 32 | 日志浏览器、监控控制台 |

每个preset单独编译；窗口resize跨越preset时允许重载另一份已编译Scene，不在热路径做任意reflow。

日志浏览器采用`desktop-wide`：左侧navigation 216 px、中央list区域、右侧或底部details surface；level应使用窄status pill/left indicator，selected使用accent outline或raised surface，而不是整行高饱和填充。

## 8. 与冻结列表ABI的关系

`virtual_list_plan`、`row_activation_plan`、`scrollbar_plan`、`list_navigation_plan`不改变。Design System只生成新的应用层`visual_component_plan`与`font_asset_manifest`，其中引用既有list ID、row tile、glyph range和detail tile；宿主启动期需证明引用对象存在、字体manifest hash匹配、component quad/glyph范围是既有render schedule的子集。

## 9. 实施顺序

1. **Theme parser + compile-time token expansion**：先替换散落颜色/间距，不改变GPU ABI。
2. **Font asset compiler**：先为日志浏览器预烘焙ASCII、数字、标点、UI icon和日志字典。
3. **Surface primitive**：固定radius/border/elevation buckets与proof。
4. **Desktop component macros**：`app-shell`、`surface`、`toolbar`、`table-header`、`status-pill`、`detail-panel`。
5. **Log browser v2**：在1280×800用新设计系统重建；原像素版本保留为`log-browser-bench`。
6. **Realtime monitor table**：验证同一token/字体/组件系统的复用性。

## 10. 验收条件

每个阶段必须同时满足以下条件：

- 新视觉属性在Racket expand期可解析为常量；
- Scene显式记录字体manifest、组件quad/glyph范围与tile依赖；
- Rust启动期拒绝未知font face、越界glyph、未声明icon或扩大tile范围；
- 真实X11/Vulkan截图显示文字、图标、surface和selection均可读；
- 原有virtual-list、scrollbar、navigation、activation、append和no-packets回归保持通过；
- 热路径仍不出现字体测量、shaping、对象遍历、GPU分配或worklist上传。
