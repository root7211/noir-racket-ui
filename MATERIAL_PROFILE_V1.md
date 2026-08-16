# Noir Material Profile v1

`Material Profile v1` 是 Noir 对 Material Design 3 的**受限、编译期实现**。它采用 Material 的语义 token、surface hierarchy、small app bar、navigation rail、card 与filled button的设计语言，但不移植传统运行时组件树、动态主题求值、自由响应式 reflow 或 ripple 动画。Material 将 token 视为可复用的设计决策，并区分 reference、system 与 component 三层；Noir 将该层级在宏展开时全部解析为不可变 Scene 数值。[1]

> `material-profile` 不是运行时theme对象。它只在一个`noir-app`的宏展开期间存在；导出的Scene、Rust host和WGSL均不会查询profile map。

## 1. 顶层声明

v1 只提供一个冻结的dark baseline：

```racket
(noir-app
  (visual-preset desktop-wide)
  (material-profile material-dark)
  (state [refresh-count 0])
  ...)
```

`(theme ...)` 与 `(material-profile ...)` **互斥**。前者是应用自定义token输入；后者是版本化、可复现的Material语义token输入。两者绝不能并存，以避免运行时或展开期发生不透明的覆盖规则。

| 项目 | v1 规则 |
|---|---|
| 可用profile | 精确为`material-dark`。 |
| 主题选择时机 | 宏展开期。 |
| token存活期 | 仅`parse-node`与所有静态lowering pass期间。 |
| 运行时theme查询 | 不存在。 |
| Scene ABI | 不新增theme map；保留既有visual、rounded、glyph与event ABI。 |
| 画布 | 示例固定使用`desktop-wide`，即1280×720与32px margin。 |

## 2. Token 映射

Material官方将颜色、字体、尺寸和组件状态视为可命名token，并建议component token尽量指向system/reference token。[1] Noir v1采用相同的**语义间接层**，但在编译期将其折叠到现有RGBA、几何、glyph placement和rounded metadata中。

| Material语义token族 | `material-dark` v1 | Noir下游产物 |
|---|---|---|
| `primary`、`on-primary`、`primary-container` | 冻结dark palette RGBA | filled button、accent surface、text颜色。 |
| `secondary-container` | 冻结dark palette RGBA | navigation rail active indicator。 |
| `surface`、`surface-container-*` | 4档静态surface色阶 | card、rail、app bar与背景quad。 |
| `on-surface`、`on-surface-variant`、`outline*` | 冻结文本/分隔语义色 | static glyph颜色、divider quad。 |
| `compact`、`control`、`card`、`panel` radius | 4、20、12、12 px | `rounded_surface_plan v1`的固定radius slot。 |
| `level-0` … `level-5` | 0 … 5 | 解析为静态elevation token；当前v1只以既有decoration表达，真实shadow留给独立plan。 |
| `sm` … `section` spacing | 8 … 48 px | 展开期layout常量。 |

Material elevation定义surface之间的z轴相对关系，并枚举0–5等级；它不要求level本身等同于某种运行时shadow实现。[2] Noir据此接受0–5的静态token，但**不**将其伪装成实时模糊阴影。`shadow_surface_plan`是后续独立工作。

## 3. 组件语法与静态lowering

所有v1 Material语法都是宏层的压缩表达。`layout_plan`中只能出现既有`stack`、`button`、`text`和`overlay`标签；禁止出现`material-*` runtime tag。

| 表面语法 | 固定输入 | primitive lowering | 不支持的动态能力 |
|---|---|---|---|
| `material-app-bar` | title、face、x/y/width、可选height/background | `surface` + title `text` + separator `overlay` | search、flexible height、scroll animation、任意actions。 |
| `material-card` | x/y/width/height、静态children、可选color/elevation | rounded `surface` | auto size、动态elevation、自由content layout。 |
| `material-filled-button` | stable IDs、label、action、face、fixed rect | background `stack` + actionable rounded `button` + label `text` | ripple、icon、loading、自由状态机。 |
| `material-nav-rail` | fixed rect、active ID、face、3–7 destinations | rounded `surface` + static destination stacks + active pill | collapsed/expanded transition、icon lookup、runtime destination diff。 |
| `material-destination` | stable ID、label ID、literal label | rail内静态`stack`与`text` | 独立使用或未声明active target。 |

Material官方将navigation rail限定在中等及更大窗口，并建议3–7个destination与固定位置；v1将这两个可验证约束直接变成语法检查。[3] Material app bar的当前页面语义与少量关键动作也被映射为固定small app bar，而非一般化toolbar。[4]

## 4. 静态证明

`tools/verify_material_profile_v1.sh`执行下列验收：

1. 全量Racket语言回归，包含profile宏的primitive-only Scene oracle；
2. 固定1280×720 Scene export，检查32个layout node、6个rounded surface和page-2 glyph placement；
3. 在宏展开期拒绝未声明的active destination、少于3个destination以及`theme`/`material-profile`混用；
4. Rust 1.87 / wgpu 30 release build；
5. 真实X11/Vulkan窗口渲染与截图；
6. 点击固定`material-refresh-button`命中区，验证action slot写入`refresh-count`，且仅patch三个预分配glyph ID地址。

```bash
bash tools/verify_material_profile_v1.sh
```

## 5. 明确非目标

v1不是Material 3的完整兼容层。下列能力被有意排除：动态配色、亮暗主题切换、任意响应式breakpoint、icon registry、ripple、自由motion、search app bar、modal rail、runtime component schema、per-frame style计算与无界文本。它们只有在能被独立表达为**有界、预分配、可证明的编译产物**时才会进入Noir。

## References

[1] [Material Design 3, *Design tokens*](https://m3.material.io/foundations/design-tokens)

[2] [Material Design 3, *Elevation tokens*](https://m3.material.io/styles/elevation/tokens)

[3] [Material Design 3, *Navigation rail*](https://m3.material.io/components/navigation-rail/overview)

[4] [Material Design 3, *App bars*](https://m3.material.io/components/app-bars/overview)
