# Noir 视觉语言 v1：现状审计

**审阅对象：** `out/log-browser-ui/15-fontc-page2-compatible-full.png` 与 `out/realtime-monitor-ui.png`
**审阅日期：** 2026-08-16

## 结论

当前示例已经具备可验证的字体资源、比例静态chrome、动态表格和组件宏，但尚未构成完整桌面视觉语言。画面仍接近“benchmark canvas上的一组矩形”，而不是具有明确空间结构、surface层级、密度系统和状态语义的桌面应用。

| 维度 | 观察 | 视觉语言v1必须补齐的内容 |
|---|---|---|
| 空间使用 | 两张1280×720截图仅使用左上小块内容区域，剩余画布大面积为空黑 | `desktop-wide`画布与主content frame；明确shell、content、side/detail区域 |
| Surface层级 | 顶栏、表头、列表、详情和按钮主要依赖不同实心色块，缺少边框、间距与层级节奏 | flat/border/raised/overlay离散elevation，surface与divider primitive |
| 信息密度 | 列表行、详情与下一行视觉重叠，动态legacy正文与比例chrome缺少明确层界 | 行密度token、固定line box、detail区隔、scissor/clip验收 |
| 状态语义 | 监控的warning/error使用整行高饱和填充，抢夺正文阅读焦点 | semantic status采用低alpha tint、左侧indicator和静态status pill，selected采用accent outline/raised层 |
| 字体角色 | 标题与列头已使用page-2比例字体；动态正文仍为legacy 5×7风格，且相对UI尺寸偏大 | type role token、标题/label/mono data角色、固定字号/line-height与可见动态正文约束 |
| 控件语言 | action bar看似可点击，但缺少统一border/hover/pressed视觉规范和控件密度 | button/pill variant、semantic action token、固定state patch颜色集合 |
| 分隔与对齐 | 列头与正文、列表与详情之间没有稳定divider体系；列的扫描节奏不足 | divider primitive、section gap、列对齐与表头/inset token |

## 不应引入的运行时机制

视觉语言改造不得引入运行时CSS、运行时theme对象、动态颜色查找、字体测量、模糊阴影、任意布局重排或组件树遍历。每个视觉variant必须在宏展开期变为固定RGBA、quad几何、glyph placement、clip、tile范围和已知instance patch。

## 视觉实现优先级

1. 语义色彩与density/elevation token；
2. 固定surface、border、divider和selected-outline primitive；
3. toolbar/header/detail/status component variant；
4. `desktop-wide`静态应用几何与布局分区；
5. 两个应用的真实截图与行/详情不重叠oracle。
