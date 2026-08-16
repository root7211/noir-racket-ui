# Material Profile v1：官方规范提取

本笔记只记录将被映射到Noir编译期产物的Material 3概念，不将官方运行时组件模型直接引入Noir。

| 官方主题 | 提取结论 | Noir v1 决策 |
|---|---|---|
| Design tokens | Material将token分为reference、system、component三类；token可表达颜色、字体、尺寸及组件状态。 | 提供固定的`material-dark` profile：Racket展开期解析reference→semantic/system→component常量，不支持运行时动态主题。 |
| Elevation | 官方推荐使用level 0–5 token；level本身描述surface相对关系，shadow独立于level定义。 | 先导出固定elevation level并让静态surface携带。视觉阴影待独立`shadow_surface_plan`实现；v1不承诺runtime elevation变化。 |
| App bar | 置顶、表达当前页面、仅保留1–2个关键动作；滚动时使用fill差异分隔内容。 | `material-app-bar` 宏只支持固定small desktop form、静态title/subtitle与最多两个固定action；不实现自由滚动动画。 |
| Navigation rail | 面向中/大窗口、固定位置、3–7 destinations；M3 active destination可用pill indicator。 | `material-nav-rail` 宏接受3–7个编译期已知destination；active indicator为固定rounded static surface，状态切换后续走既有有限slot patch。 |
| Component state | 官方component tokens按enabled/disabled/hover等state组织。 | v1只导出resting静态token；现有hover/selection色patch可消费预计算state颜色，但不实现ripple。 |

## Sources

1. Material Design 3, "Design tokens", https://m3.material.io/foundations/design-tokens — token、reference/system/component层级与状态组织。
2. Material Design 3, "Elevation", https://m3.material.io/styles/elevation/tokens — level 0–5及component resting level。
3. Material Design 3, "Navigation rail", https://m3.material.io/components/navigation-rail/overview — rail窗口范围、3–7 destination与active indicator。
4. Material Design 3, "App bars", https://m3.material.io/components/app-bars/overview — app bar语义、关键动作数量及scroll separation。
