# Noir Desktop Visual Language v2

**作者：Manus AI**

## 目标

Noir v2以EUI-NEO的现代工具型桌面界面为质量参考，但只吸收能够lower为固定primitive、字体placement、颜色常量和有限状态patch的视觉规则。EUI-NEO把排版、spacing、radius、control size拆成离散token，并让Card/Button等组件继续组合底层DSL图元；Noir采用相同的系统化思想，但将所有值提前求值，不保留运行时theme或组件对象。[1] [2]

> **视觉语言也是编译产物：设计选择最终必须变成地址、尺寸、颜色、层级和有限状态表。**

## 应用骨架

`workspace-shell v2`采用固定1280×720 desktop-wide canvas，32px外边距和以下不可变区域：

| 区域 | 固定几何 | 语义 |
|---|---:|---|
| Brand rail | 168×656px | 产品标识、应用类型、数据源/状态摘要 |
| Workspace | 996×656px | header、summary strip、table card、detail/action footer |
| Header | 996×76px | 32px display title、13px eyebrow/meta、右侧compact action |
| Summary strip | 996×72px | 三个或四个静态指标/状态分组 |
| Table card | 996×356px | section title、column header、固定row viewport、scrollbar |
| Detail footer | 996×118px | selected-row context与主要操作 |

v2不引入响应式布局。上述区域在Racket宏展开期确定；两个应用只替换静态标签、状态语义和既有列表/detail/action子树。

## 色彩token

两个应用共享同一Neutral Ink基底与Primary Blue。监控绿色只作为success语义，不再替代全局accent。

| Token | RGBA/Hex | 用途 |
|---|---|---|
| `canvas` | `#0B0D12` | 窗口最底层 |
| `rail` | `#10131B` | 左侧品牌rail |
| `surface` | `#171A23` | 主card |
| `surface-raised` | `#1E222D` | header/detail/hover层 |
| `surface-hover` | `#262B37` | 可交互hover |
| `surface-active` | `#303746` | pressed/selected边界层 |
| `border-subtle` | `#2B313E` | card和row分隔 |
| `border-strong` | `#465268` | focus与active outline |
| `text-primary` | `#F3F6FB` | 标题/主要数据 |
| `text-secondary` | `#BBC3D1` | 正文与标签 |
| `text-muted` | `#7E899A` | 辅助说明 |
| `accent` | `#4D8DFF` | 选中、主按钮、focus |
| `accent-muted` | `#1D3766` | active rail与低压强调 |
| `success` | `#3CCB9C` | nominal/online |
| `warning` | `#F2B84B` | warn/slow |
| `danger` | `#EF6B82` | error/offline |
| `info` | `#69A6FF` | debug/information |

状态行的语义由三层组成：4px status rail、低alpha row tint和文本；禁止用高饱和色覆盖整行。

## 排版层级

静态page-2字形新增编译期`font-scale`，只缩放manifest metrics与固定quad，不改变UV、atlas或运行时资源。v2的层级为：

| Role | Base face / scale | 目标像素 | 用途 |
|---|---:|---:|---|
| Display | desktop sans / 1.55 | 28px | 应用标题 |
| Section title | desktop sans / 1.10 | 20px | Card标题 |
| Control | desktop sans / 0.90 | 16px | 按钮/列头 |
| Meta | desktop sans / 0.72 | 13px | eyebrow、状态说明 |
| Data body | tabular mono / 1.00 | 16px | page-3固定cell正文 |

`font-scale`是static text专属属性，范围封闭为`0.70–1.60`；dynamic text与page-3 cell禁止使用该属性。

## 尺度阶梯

| 类别 | v2离散值 |
|---|---|
| Spacing | 1, 2, 4, 6, 8, 10, 12, 16, 20, 24, 32, 40px |
| Radius | 4, 6, 8, 10, 12, 16, 18px |
| Control height | 28, 36, 40, 44px |
| Row height | 32px |
| Border | 1px；focus 2px |

这些阶梯参考EUI-NEO的token分组，但Noir只保留当前两个桌面应用实际使用的子集。[1]

## 组件变体

| 组件 | v2 lowering | 运行时权限 |
|---|---|---|
| `workspace-shell` | 固定rail + workspace两栏stack | 无 |
| `page-header` | eyebrow、display title、meta、compact action | action沿用既有event slot |
| `summary-strip` | 3–4个静态mini-surface | 无，后续可绑定固定state slot |
| `table-card` | section header、column header、list viewport、scrollbar | 列表沿用冻结ABI |
| `status-rail` | 4px固定quad + row tint | 颜色写入仍使用既有row color offset |
| `detail-card` | title/meta + 受控detail glyph clip | detail只写既有固定glyph范围 |
| `action-button filled` | accent fill + hover/pressed色表 + 12px radius | 既有event/animation track |
| `action-button outline` | transparent/surface fill + 1px accent border | 既有event/animation track |
| `badge` | fixed pill background + static page-2 label | 无 |

v2暂不支持模糊阴影。Elevation使用两层固定quad模拟：外层暗色/边框，内层surface；这是可确定且跨wgpu后端一致的近似。

## 验收标准

两个示例必须在真实X11/Vulkan截图中满足：内容覆盖整个工作区；标题、section、meta和data形成明确层级；表格与detail不重叠；主操作不再是整宽色带；WARN/ERROR以status rail与低压tint表达；所有既有End、选择、Enter、batch refresh和零GPU写入oracle继续通过。

Scene不得出现`workspace-shell`等组件tag；组件必须完全内联为现有primitive。与视觉无关的`virtual_list_plan`、`dynamic_font_cell_plan`、row activation、data update和worklist ABI不得更改版本。

## References

[1]: https://github.com/sudoevolve/EUI-NEO/blob/main/components/theme.h "EUI-NEO theme tokens"
[2]: https://github.com/sudoevolve/EUI-NEO/blob/main/docs/%E7%BB%84%E4%BB%B6.md "EUI-NEO components documentation"
[3]: https://github.com/sudoevolve/EUI-NEO "EUI-NEO repository and preview gallery"
