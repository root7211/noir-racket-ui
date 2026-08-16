# Rounded Surface Plan v1：编译期 SDF 圆角与抗锯齿交付报告

**状态：已完成并通过全链回归。** 本次交付将 Noir 桌面视觉语言从硬矩形 surface 推进到真实的 **SDF rounded rectangle + 1px 抗锯齿 coverage**。圆角不是运行时主题查询、组件对象状态或临时 GPU 修饰；它由 `#lang noir/ui` 的宏展开期收集，作为冻结的 `rounded_surface_plan` 输出，并在 Rust/wgpu 创建窗口和 GPU 资源之前反向证明。

> 本实现只改变静态 desktop chrome 的 fragment coverage。它不改变 `QuadInstance` 44-byte ABI、glyph placement、虚拟列表 row arena、状态写入范围、tile/worklist、事件映射或每帧 draw range。

| 交付项 | 结果 | 关键证据 |
|---|---|---|
| Racket 宏与 Scene ABI | 通过 | 输出 `noir-rounded-surface-plan-v1@1`、固定 `aa_width_px = 1.0` 与实例地址。 |
| Rust 1.87 / wgpu 30 后端 | 通过 | `GpuRoundedSurfaceMeta` 以只读 storage buffer 绑定静态 quad pipeline。 |
| WGSL SDF 渲染 | 通过 | `rounded_box_sdf`、smoothstep coverage、flat instance index 经 Vulkan shader validation。 |
| 日志浏览器真实帧 | 通过 | `out/log-browser-rounded-v3.png`，启动日志确认 9 个圆角 surface。 |
| 实时监控真实帧 | 通过 | `out/realtime-monitor-rounded-v3.png`，启动日志确认 9 个圆角 surface。 |
| 结构、攻击与交互回归 | 通过 | 总入口输出 `ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS`。 |

## 1. 设计目标与实现边界

Noir 的主线是把 UI 的依赖、几何、资源和写入范围在编译期降低为有限、可验证的执行计划。圆角必须遵循同一条原则：运行时不得选择半径、增加圆角对象、移动 metadata 指针，也不得变更抗锯齿规则。因此 v1 采用了**独立、静态、按实例槽寻址的 metadata 表**，而没有向可变 `QuadInstance` 插入 radius 字段。

| 维度 | v1 决策 | 为什么符合 Noir 的最短路径 |
|---|---|---|
| 计划来源 | Racket 展开期从显式 `#:radius` 的 `stack`/`button` 静态节点收集 | 没有运行时组件遍历或 style lookup。 |
| 地址模型 | `instance_offset / 44` 得到固定 metadata slot | 复用既有静态 quad 分配，不扩大 instance ABI。 |
| GPU 数据 | 每槽 `vec4<f32> = [radius, aa_width, width, height]` | 16-byte 对齐、单次启动上传、每帧零 metadata 写入。 |
| fragment 路径 | 零 radius 直接返回原颜色；正 radius 做 SDF coverage | 保持基线 Scene 和非 surface quad 的硬矩形兼容性。 |
| 允许目标 | 静态 `stack`/`button` chrome | 明确排除 row、scrollbar、glyph、caret 和任何事件可变 geometry。 |
| AA 规则 | v1 固定 1px | 使视觉输出和 proof 都是确定性的。 |

`page-header`、`metric-tile`、`detail-panel` 与带 visual token 的 action button 宏会携带 `(theme-radius card)` 声明；宏展开后仍只留下基础 primitive。因而 Scene 中不出现高层组件 tag，也不引入运行时组件树。

## 2. ABI 与 renderer 路径

Scene 增加显式 `rounded_surface_plan` 字段。桌面场景输出 nonempty v1 plan；bench fixture 可显式输出 `false`，用于保留硬矩形兼容路径。完整接口见 [`ROUNDED_SURFACE_PLAN_ABI_V1.md`](ROUNDED_SURFACE_PLAN_ABI_V1.md)。

```text
Racket explicit #:radius
  → compile-rounded-surface-plan
  → Scene rounded_surface_plan (fixed IDs, QuadInstance offsets, geometry)
  → Rust startup proof
  → immutable GPU storage buffer (one vec4 / instance slot)
  → WGSL fs_main(instance_index)
  → SDF signed distance + 1px smoothstep coverage
```

WGSL 入口的整数实例索引以 `@interpolate(flat)` 标注，从而符合 wgpu 30 / Naga 的整数 I/O 验证规则。v1 的最终 coverage 语义为：

```text
half_size = [width, height] / 2
point     = (local_uv - 0.5) * [width, height]
distance  = rounded_box_sdf(point, half_size, radius)
coverage  = 1 - smoothstep(-aa, aa, distance)
alpha     = source_alpha * coverage
```

这意味着圆角只影响边角 fragment alpha，保留所有已证明的顶点提交、draw range、tile 裁剪和运行时局部 patch 地址。

## 3. 启动期 proof 与防篡改策略

Rust 的 `compiler_rounded_surface_plan` 在创建 rounded metadata buffer、pipeline 或窗口之前对未信任 Scene JSON 进行验证。它要求 schema/revision 与固定 AA 宽度完全匹配，验证 entry ID、offset、44-byte 对齐、slot 唯一性、geometry 和半径上限，并反向限制 tag 仅能是静态 `stack` 或 `button`。desktop-wide Scene 若把计划篡改为 `false` 会被直接拒绝，杜绝“静默降级为硬矩形”的绕过路径。

| 攻击样本 | 篡改方式 | 实际拒绝证据 |
|---|---|---|
| `radius` | 将首个 `radius_px` 改为超过允许半径 | `rounded surface log-app-bar geometry/radius/AA disagrees with compiler layout` |
| `offset` | 将固定 `instance_offset` 偏移 44 bytes | `rounded surface log-app-bar must target its own static stack/button layout` |
| `geometry` | 将计划宽度增加 1px | `rounded surface log-app-bar geometry/radius/AA disagrees with compiler layout` |
| `disable` | 将 desktop-wide `rounded_surface_plan` 改为 `false` | `desktop-wide visual Scene may not disable rounded_surface_plan v1` |

篡改工具为 [`tools/mutate_rounded_surface_scene.py`](tools/mutate_rounded_surface_scene.py)，回归入口为 [`tools/verify_rounded_surface_plan.sh`](tools/verify_rounded_surface_plan.sh)。攻击在事件循环开始前失败，因而不会产生窗口或 GPU 首帧副作用。

## 4. 验证方法与结果

正式回归按以下顺序运行：Racket language tests、Rust 1.87 release build、两个真实 Scene export、visual language v2 structural oracle、rounded Scene oracle、四类篡改拒绝、两个真实 X11/Vulkan 截图，以及日志浏览器和实时监控表格既有键鼠交互回归。

```bash
bash tools/verify_rounded_surface_plan.sh
```

| 验证层 | 结果 | 观测值 |
|---|---|---|
| Racket 语言测试 | 通过 | 宏展开与既有 Scene/resource tests 成功。 |
| Rust release build | 通过 | Rust 1.87、wgpu 30.0.0、X11-only host。 |
| 视觉结构 oracle | 通过 | 两个 Scene 均为 1280×720、60 layout nodes、primitive-only lowering、固定 10,000/4/4×32 list geometry。 |
| rounded Scene oracle | 通过 | 两应用均含 v1 plan，固定 AA，至少 9 个正半径 entries。 |
| X11/Vulkan 正向路径 | 通过 | 每应用启动日志：`surfaces=9 metadata-slots=60 aa-width=1px immutable-instance-slots`。 |
| 日志浏览器交互 | 通过 | tail append、End、选择 ERROR、Enter 详情激活仍走原有 fixed slots。 |
| 实时监控交互 | 通过 | 可见性分流、数值刷新、选择与动作回归成功。 |

最终总入口记录：

```text
rounded surface Scene oracle: PASS
log browser regression: PASS
realtime monitor regression: PASS
ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS
```

## 5. 视觉审阅产物

两张真实 Vulkan/X11 v3 截图分别展示 app bar、metric tile、table card、detail card 与主按钮的圆角表面：

- [`out/log-browser-rounded-v3.png`](out/log-browser-rounded-v3.png)
- [`out/realtime-monitor-rounded-v3.png`](out/realtime-monitor-rounded-v3.png)

并排对照图在完全相同的 1280×720 Scene geometry、文本资产、列表动作与 executor 下，只替换 rounded metadata：

- [`out/log-browser-rounded-v2-v3-comparison.png`](out/log-browser-rounded-v2-v3-comparison.png)
- [`out/realtime-monitor-rounded-v2-v3-comparison.png`](out/realtime-monitor-rounded-v2-v3-comparison.png)

对比显示 v3 在 card、header、tile 与 button 边界产生连续的圆角轮廓，同时保留 v2 的网格、字体、状态 tint、row geometry 与 interaction ABI。此变更是**视觉层功能增量**，而不是布局或运行时数据通路重写。

## 6. 已修复的实现问题

在最终真实 GPU 回归中，wgpu 30/Naga 首先拒绝了 WGSL 局部变量名 `meta`，因为它是保留字；随后又拒绝未显式 flat 插值的 `u32` varying。已分别改名为 `surface_data`，并将实例索引声明为 `@interpolate(flat)`。修复后 shader 创建、两应用 metadata proof 与 X11/Vulkan frame capture 全部成功。此过程说明最终验收依赖真实 wgpu shader validation，而不能仅依赖 Racket 序列化或 Rust 编译成功。

## 7. 非目标与下一步

v1 有意不实现 shadow、per-corner radius、动态 radius、hover radius 插值、blur 或 runtime style override。这些能力若需要加入，必须以独立、冻结且可证明的计划表达，不能把任意视觉对象带回运行时。

下一步应是 **visual rendering v3 第二部分：`shadow_surface_plan v1`**。推荐用编译期固定的多层 shadow quad（每层固定 inset、offset、alpha、instance slot）作为独立计划；它应复用 static quad pipeline 或明确的新 pass，并保持 `QuadInstance`、glyph 和虚拟列表动态槽不变。随后再将静态 page-2 chrome 文案迁移到正常大小写，以继续改善可读性，而不扩大动态文本域。
