# `shadow_surface_plan v1` 交付报告

**作者：Manus AI**

**范围：Noir 视觉渲染 v3 第二部分**

**状态：已在 Rust 1.87、wgpu 30、X11/Vulkan 环境完成验证**

## 摘要

本次实现将 Noir 的固定 `elevation` token 从静态语义色阶扩展为可执行的、**编译器证明的多层阴影计划**。Material Profile 示例中三张 level-1 card 在 Racket 宏展开期各生成两层 shadow，共六个 immutable shadow quad。运行时不会分配组件对象、搜索elevation source、计算blur、读取主题或改写已有 UI instance buffer；host 只在启动期验证计划，然后在固定顺序中绘制预分配shadow pass。

Material Design 将 elevation level 用来描述surface相对关系，而不将其限定为单一shadow算法。[1] Noir 因此选择了受限实现：以 `0–5` 级别映射到固定的两层ambient SDF recipe，而不是引入动态光照、滤镜或自由参数。

| 项目 | 最终结果 |
|---|---|
| Scene ABI | `noir-shadow-surface-plan-v1@1` |
| Material示例的elevated source | 3个 level-1 card |
| 编译期shadow layer | 6个，且每source固定2层 |
| GPU metadata ABI | 每layer 16 bytes：`[radius, blur, source_width, source_height]` |
| 既有QuadInstance ABI | 44 bytes，未修改 |
| 运行时shadow更新 | 0；全为启动期上传的不可变buffer |
| 正向真实窗口 | X11/Vulkan通过，`layers=6 elevated-sources=3` |
| 篡改拒绝 | `blur`、`offset`、`geometry`、`disable` 四类均在启动期拒绝 |

## 编译模型

Racket `surface` parser 已解析的literal elevation仅保留为编译器内部属性；它会被写入 `layout_plan.elevation`，以支持host进行反向proof，但不会成为可变样式对象。对 `desktop-wide` preset，`compile-shadow-surface-plan` 只接受带固定正radius的静态 `stack` surface，读取其已经冻结的layout rect与44-byte instance offset，并生成layer表。

level-1的外层是 `blur=7px, opacity=0.055`，随后绘制内层 `blur=3px, opacity=0.140`。排序是编译器canonical的：source ID升序，单一source内由大blur到小blur。阴影真实quad的rect是source rect四边各扩张blur；source本体在后续static pass中覆盖shadow内部，只留下外缘软化带。

> 这不是“每帧模糊一个卡片”。Noir在宏展开期已经知道每个source、每层rect、颜色alpha和SDF参数；运行时只提交一个固定的shadow instance range。

## GPU路径与关键修复

shadow使用独立的 `host_shadow.wgsl` pipeline。fragment shader从只读storage buffer按`instance_index`读取16-byte metadata，在扩张quad的局部像素空间计算source rounded box SDF，并用`fwidth`和固定blur区间生成coverage。它不读取字体、state、event map、theme或runtime layout。

实现初期的pass顺序是 `shadow → full static scene`。真实截图哈希与之前完全一致，表明opaque root canvas quad覆盖了已绘制的shadow。该问题已被诊断并修复为以下固定顺序：

```text
root canvas instance → immutable shadow layers → remaining static instances → glyph placements
```

修复后，当前真实帧相对已发布无shadow基线出现 **24,612个像素**变化；差异集中在三张elevated card的周边。该数据来自同一1280×720 X11/Vulkan Material Scene的像素比较，审阅记录保存在 `out/shadow_surface_visual_review.txt`。

## 启动期proof与攻击拒绝

Rust在创建shadow metadata buffer、shadow instance buffer和pipeline前验证schema/revision、desktop禁用规则、source ID、source 44-byte offset、layout tag、elevation、layer编号、finite geometry、radius、recipe blur/opacity和完整source coverage。host同时反算NDC layout的像素rect，要求每个shadow rect精确等于source rect按blur扩张的结果。

| 攻击 | 修改内容 | 启动期拒绝证据 |
|---|---|---|
| `blur` | 将首个layer的blur增加1px | `geometry/recipe disagrees with compiler layout` |
| `offset` | 将`source_instance_offset`偏移44 bytes | `source/elevation/instance offset disagrees with frozen layout` |
| `geometry` | 将扩张quad width增加1px | `geometry/recipe disagrees with compiler layout` |
| `disable` | 将desktop Scene plan替换为`false` | `desktop-wide visual Scene may not disable shadow_surface_plan v1` |

`tools/verify_shadow_surface_plan.sh` 组合执行Material正向Racket/Rust/X11回归以及上述四份结构化攻击样本。最终标记为：

```text
MATERIAL_PROFILE_V1_REGRESSION: PASS
SHADOW_SURFACE_PLAN_V1_REGRESSION: PASS
ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS
```

最后一项确认shadow ABI、Scene字段和pass没有破坏日志浏览器、实时监控表格、圆角metadata、虚拟列表滚动或既有键鼠交互。

## 性能边界

本实现新增的成本由每个elevated source的固定两次instanced quad绘制组成。Material fixture因而新增6个静态shadow instance；没有CPU per-frame blur、没有queue写入、没有glyph write、没有动态bind group、没有命令重新排序。局部dynamic action若未清除card背景，不会重画shadow；full canvas或静态tile重建时按相同不可变buffer再次提交。

| 允许 | 明确不允许 |
|---|---|
| 编译期固定0–5 elevation | 运行时请求新的elevation或blur |
| 每source两层canonical ambient shadow | 自定义层数、颜色、方向或阴影滤镜 |
| 固定rect、radius、alpha和source offset | 事件期移动shadow或重算layout |
| 只读GPU metadata及instance buffer | 改写page-2/page-3 glyph、virtual-row或action写域 |

## 审阅产物与后续工作

真实after截图为 [`out/material-profile-dashboard-v1.png`](out/material-profile-dashboard-v1.png)，同场景before/after比较板为 [`out/material-profile-shadow-v1-comparison.png`](out/material-profile-shadow-v1-comparison.png)。该对照图保留圆角、文本和按钮交互上下文，并突出card周边的阴影差异。

下一步应实现 `navigation_selection_plan v1`，让3–7个已声明Material rail destination在固定state/action slot中切换active pill。它应继续复用固定geometry与局部quad color patch，而非引入通用router或运行时组件树。

## 参考资料

[1]: https://m3.material.io/styles/elevation/tokens "Material Design 3 — Elevation tokens"
[2]: https://m3.material.io/foundations/design-tokens "Material Design 3 — Design tokens"
