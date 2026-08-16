# Material Profile v1：编译期 Material Design 迁移交付报告

**状态：已完成。** Noir 已实现 `material-dark`，这是一个把 Material Design 3 的语义token与部分桌面组件转化为**编译期Scene/GPU计划**的受限profile。它不将Material作为运行时widget库移植；相反，颜色、space、type、shape、elevation、组件几何、glyph placement、rounding slot与action write均在Racket宏展开期固定。

> Material的贡献是设计语言；Noir的贡献是执行模型。该实现保留前者的语义层级，但拒绝后者在常见UI框架中依赖的运行时theme对象、组件树遍历和自由layout重算。[1]

| 交付物 | 已实现结果 |
|---|---|
| 编译期profile | `(material-profile material-dark)`，与手写`theme`互斥。 |
| Token层 | Material语义颜色、surface阶梯、shape、space、type与level 0–5 elevation token。 |
| 宏组件 | `material-app-bar`、`material-card`、`material-filled-button`、`material-nav-rail`、`material-destination`。 |
| 示例 | `examples/material-profile-dashboard.rkt`，固定1280×720 desktop workspace。 |
| Scene证明 | 32个primitive layout node、6个rounded metadata surface、221个page-2静态glyph placement。 |
| 真实交互 | X11点击filled button后，只执行一条固定action、一个state slot写入与3个glyph ID patch。 |

## 1. 实现概要

Material官方说明token是设计系统的可复用设计决定，并使用reference、system、component三层组织从颜色、字体到组件状态的关系。[1] Noir用`material-profile-table`将这三层在展开期折叠为已有`theme-token-value`接口可消费的常量，因而`layout_plan`中的RGBA和几何已经是最终值。Scene JSON不持有profile map；Rust/wgpu宿主也不加载、查询或覆盖任何Material token。

| Material概念 | Noir v1静态产物 | 运行时成本 |
|---|---|---|
| `surface-container-*` hierarchy | 静态quad RGBA与固定card geometry | 无theme lookup。 |
| shape token | `rounded_surface_plan v1`按`instance_offset / 44`读取的不可变metadata | 启动期一次上传；每帧零metadata写入。 |
| active navigation indicator | 一个固定rounded `stack` slot | 不创建导航组件或widget树。 |
| small app bar | static surface、title glyph placement与separator quad | 无滚动/height推导。 |
| filled button | 固定button event map、state/action slot与预分配dynamic glyph cell | 点击仅写已知地址。 |
| elevation level | 展开期整数token | 当前无伪动态shadow；后续由专用shadow plan承载。 |

Material对navigation rail给出固定位置、3–7个destination的指导；Noir将它们设为严格宏输入而不是运行时推荐值。[3] 同样，app bar的页面标题语义被限定为fixed small form，符合桌面Scene几何必须可在展开期确定的原则。[4]

## 2. 宏与Scene不变量

所有`material-*`组件会立即降级为既有primitive。结构oracle拒绝任何出现在layout中的高层Material tag，并验证以下稳定ID：`material-nav-rail`、`material-overview`、`material-app-bar`、三张card与`material-refresh-button`。任何Material组件实例都不需要新Rust结构体、WGSL分支、Scene ABI字段或runtime dispatch类型。

导航rail的selected pill、三张card和filled button组成6个`rounded_surface_plan v1` entry；它们均采用固定1px AA，半径满足`radius ≤ min(width,height)/2`。迁移过程中，初始“无限pill”半径被既有rounded proof拒绝，随后被降低为对48px indicator合法的20px `control` radius。这证明Material语义必须服从Noir的几何可证明性，而不是绕过它。

## 3. 真实验证结果

完整入口为：

```bash
bash tools/verify_material_profile_v1.sh
```

| 验证层 | 结果 | 关键观测 |
|---|---|---|
| Racket全量语言回归 | 通过 | `Noir Cost Model language checks passed.` |
| Material Scene oracle | 通过 | 32 layout nodes、6 rounded surfaces、221 page-2 static glyphs。 |
| 未声明active destination | 拒绝 | `#:active must name one declared material-destination`。 |
| 少于3个destination | 拒绝 | `requires 3 to 7 literal material-destination children`。 |
| `theme`与profile混用 | 拒绝 | `mutually exclusive compile-time token sources`。 |
| Rust 1.87 / wgpu 30 | 通过 | release host成功构建并加载Scene。 |
| 真实X11/Vulkan | 通过 | host记录`compiler rounded surfaces: v1 surfaces=6 metadata-slots=32`。 |
| 按钮交互 | 通过 | `event-map dispatch: material-refresh`、固定state slot更新与3个glyph patch。 |

真实截图为 [`out/material-profile-dashboard-v1.png`](out/material-profile-dashboard-v1.png)。它展示静态surface层次、rail active pill、card圆角、small app bar和filled button均由现有quad/glyph路径绘制。截图来自实际X11窗口与Vulkan/llvmpipe执行，并非设计mockup。

## 4. 性能与架构结论

此实现没有把Material的抽象层转化为Noir运行时开销。profile只在宏展开期存在，组件只产生有限primitive，文本资源只产生固定atlas placement，rounded surface只有初始化期storage metadata，点击只触及已证明的action和glyph地址。因此它与Noir的核心承诺一致：**运行时执行既定最短路径，而不是重新解释设计系统。**

| 运行时操作 | 是否发生 |
|---|---|
| theme/profile hash查询 | 否。 |
| 组件树遍历或diff | 否。 |
| navigation rail列表分配 | 否。 |
| 动态radius/elevation计算 | 否。 |
| button ripple实例创建 | 否。 |
| `material-refresh` state计算 | 仅固定slot加1。 |
| 文本更新 | 仅3个固定glyph ID word patch。 |

## 5. 边界与下一步

v1并不声称完整实现Material 3。动态颜色、亮暗切换、icons、ripple、自由响应式重排、可折叠rail、search app bar、modal dialogs和动画曲线均被有意排除。下一步应在已经冻结的rounded surface基础上实现 **`shadow_surface_plan v1`**，再为Material elevation level 1–3提供编译期固定的多层shadow quad。此后可设计受限的`navigation selection plan`，使3–7个固定destination在有限state slot中切换active indicator，而无需引入通用路由器。

完整语言接口、token表与约束见 [`MATERIAL_PROFILE_V1.md`](MATERIAL_PROFILE_V1.md)。

## References

[1] [Material Design 3, *Design tokens*](https://m3.material.io/foundations/design-tokens)

[2] [Material Design 3, *Elevation tokens*](https://m3.material.io/styles/elevation/tokens)

[3] [Material Design 3, *Navigation rail*](https://m3.material.io/components/navigation-rail/overview)

[4] [Material Design 3, *App bars*](https://m3.material.io/components/app-bars/overview)
