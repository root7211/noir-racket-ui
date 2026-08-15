# SLUG 与 Noir：直接GPU轮廓文本的技术评估

**作者：Manus AI**  
**结论：** SLUG 是让 Noir 获得桌面级高保真字体的极强候选，但不应作为第一版日志表格文本的唯一渲染后端。它最适合成为 Noir 编译期字体资产管线中的 **`vector-outline` 可选renderer**：用于大标题、可缩放详情、缩放画布和3D/透视UI；标准长列表正文仍应优先使用预烘焙SDF/MSDF或灰度atlas。

## 1. SLUG 是什么

SLUG（Eric Lengyel 的 *GPU-Centered Font Rendering Directly from Glyph Outlines*）不把字形预先栅格化成位图或距离场。它把TrueType/OpenType的二次Bezier轮廓转换为GPU可读取的曲线数据；每个glyph仍只提交一个包围矩形quad，但fragment shader直接从曲线轮廓求该像素的覆盖率。[1] [2]

它的目标不是“少一个draw call”，而是解决传统直接曲线GPU文字在有限浮点精度下会出现裂纹、shimmer和边缘错误的问题。SLUG使用鲁棒的二次方程root classification与nonzero winding rule；它分别沿水平、垂直方向考虑曲线交叉，计算分数coverage并组合结果，以抗锯齿方式输出glyph。[1] [2]

| 层 | SLUG的固定数据 | 每个fragment的工作 |
|---|---|---|
| Font asset | 二次Bezier控制点、glyph metric、band索引 | 从glyph/band确定有关曲线 |
| Glyph instance | glyph ID、quad bounds、transform、颜色 | 在quad覆盖的pixel求inside/outside与coverage |
| Coverage | horizontal/vertical band划分 | winding累计、边缘coverage、混合输出 |
| 小字号 | projection-aware dilation参数 | 扩大需要采样的边界，减少细笔画消失 |

SLUG还用horizontal/vertical **bands** 将曲线分配到若干矩形slice。fragment不必遍历glyph的所有曲线，只读取自己所在band可能影响winding的曲线。[1] 动态dilation则依据model-view-projection变换扩张glyph的四边形，避免小字号和投影缩小时潜在覆盖像素根本没有进入rasterization。[1]

## 2. 为什么它可能彻底改善Noir的视觉质量

Noir目前的字形是有限像素atlas。它的优点是placement、UV、glyph cell和写入范围非常容易在编译期证明；缺点是字体形状、字号层级、中文覆盖、图标与缩放质量都受到atlas分辨率和预置字形限制。

SLUG允许Noir保留“**一glyph一quad**”的实例模型，却将quad内的coverage从5×7像素采样替换为真正outline求值。因此它能提供：

| 视觉能力 | 对日志浏览器/桌面GUI的意义 |
|---|---|
| 任意缩放下的清晰字形 | 标题、列表正文、详情和大屏DPI可共用同一font asset，不需要每个字号重新画像素字。 |
| 高质量比例字体 | 可以使用Inter、Noto Sans、JetBrains Mono等经过设计的字形、字距和字重。 |
| 真实icon字体/outline图标 | 工具栏、导航和level语义不再依赖ASCII字符模拟。 |
| projective变换稳定性 | 未来Noir若做3D桌面、缩放画布或动画标题，避免SDF常见的阈值/采样失真。 |
| 不依赖巨型多尺寸atlas | 资源随outline复杂度增长，而不是随目标分辨率和字号笛卡尔积增长。 |

这会修复Noir当前“框架正确但界面像debug overlay”的主要根因：**文字不是装饰，而是桌面UI信息层级的主体。**

## 3. 它不是无条件更快

SLUG的优势在视觉保真和几何独立性，并不代表它在所有GUI场景都胜过atlas。一个灰度/MSDF atlas glyph通常是一次纹理采样加少量coverage计算；SLUGglyph的quad内每个fragment还要访问band/curve数据、做曲线求根、winding累计与coverage合成。其成本随glyph屏幕面积、band曲线密度和可见文本量上升。

Metal by Example的示例也明确说明其sample不是最大化鲁棒性/性能的生产实现：它按text run单独draw，资源有冗余绑定，font atlas未合并；作者建议按共享资源合并run以降低draw call。[1] 因此不应把示例shader直接翻译到WGSL后称为Noir生产路径。

| 工作负载 | 推荐Noir字体后端 | 原因 |
|---|---|---|
| 10,000行日志的3条可见正文 | MSDF/灰度atlas优先 | 小字体、文本量大、无投影；采样成本低，atlas write范围已可证明。 |
| 顶部display标题、详情大文本 | SLUG优先 | glyph面积大、视觉焦点强，outline质量收益明显。 |
| 2D缩放画布、图表标注 | SLUG优先 | 连续缩放会暴露atlas分辨率与SDF阈值问题。 |
| 3D/projective文字 | SLUG优先 | 正是算法的强项。 |
| emoji、复杂脚本、任意输入 | 先交给离线shaping/预生成atlas | SLUG只解决rasterization，不替代Harfbuzz/Core Text的shaping。 |

## 4. 与Noir编译期模型的最佳结合方式

SLUG不必引入运行时字体解析。Noir应把它前移为构建期数据编译：

```text
TTF/OTF + declared coverage
        ↓  (noir-fontc at build time)
SLUG outline blob: curve buffers + band tables + glyph metrics + license manifest
        ↓  (Racket macro expansion)
font-face id + glyph ids + fixed placements + static draw ranges + glyph class budget
        ↓  (Scene JSON)
Rust/wgpu uploads immutable SLUG buffers once
        ↓
input → fixed state slot → instance color/transform/text-cell patch → local tile draw
```

Racket不保存运行时font object，只保存`font-face-id`、glyph ID、advance、quad bounds、outline class和预先证明的tile/worklist范围。Rust启动期验证font manifest hash、glyph ID range、curve/band buffer offsets、glyph class预算与draw-range subrange；热路径只patch颜色、位置或预分配cell内容。

建议定义独立、版本化的`slug_font_asset_plan`，而不是修改已冻结的`virtual_list_plan`。它应至少包含：

| 字段 | 用途 |
|---|---|
| `schema` / `revision` / `font_manifest_hash` | 防止错误字体blob与Scene组合。 |
| `font_face_id`、`glyph_id_domain` | 证明glyph索引合法。 |
| `curve_buffer_range`、`h_band_range`、`v_band_range` | 限定shader可访问的outline数据。 |
| `glyph_complexity_class` | 将每glyph band曲线数限制在固定budget，避免异常字体破坏fragment上界。 |
| `renderer_kind` | `atlas-gray`、`atlas-msdf`或`slug-outline`，由编译器选择。 |
| `placement_draw_range`、`tile_mask`、`worklist` | 复用Noir已有局部提交协议。 |

## 5. 必须先解决的文本边界

SLUG是**rasterizer**，不是完整text system。它并不替代字形选择、kerning、ligature、bidi、组合字符、行断行与fallback。Metal示例使用Core Text做layout和shaping，并明确建议把这些复杂性委托给成熟text库。[1]

Noir要维持编译期路径，应采用分层策略：

1. UI固定文案、列头、button标签、title和预定义detail模板：**构建期shape**，最安全。
2. 固定词典日志（level、service名、已知message catalog）：构建期shape，运行时只选template/glyph cell。
3. 外部任意日志文本：先不承诺SLUG实时shaping；使用固定字典编码、truncation table或明确的fallback文本。若未来支持任意文本，应在受控后台线程shape进固定ring，然后把shape result作为显式data-update artifact提交，而不能让renderer随意处理字符串。

## 6. 实施路线

### Phase A — Font compiler without SLUG shader

首先实现`noir-fontc`和`font_asset_manifest`，但同时生成灰度/MSDF atlas和glyph metrics。用Inter/Noto Sans/JetBrains Mono替换当前5×7 atlas，并在1280×800日志浏览器中证明：字体、icon、token和desktop layout使Noir界面达到可用质量。

### Phase B — SLUG asset backend

将OpenType quadratic outline转换为SLUG curve/band buffers，生成可由WGSL读取的storage buffers或纹理。优先实现ASCII、数字、UI icon及日志静态字典。建立CPU reference rasterizer与GPU golden-image oracle，覆盖小字号、旋转、缩放、曲线相切和hole glyph。

### Phase C — Hybrid renderer selection

在Racket中增加：

```racket
(text-style desktop-title #:font inter-display #:renderer slug-outline)
(text-style log-body #:font jetbrains-mono #:renderer atlas-msdf)
```

编译器根据font style、字体像素高度、transform class、可见glyph预算与profile选择backend；每种style具有固定renderer，运行时不做启发式切换。

### Phase D — Optional 3D / zoom canvas

只有在Phase C稳定后，把SLUG用于Noir的zoomable graph、3D world-space label或动画hero text。它不应先用于高频、小字号、长文本row的默认scroll热路径。

## 7. 结论

SLUG不是“让GUI自动漂亮”的算法；它解决的是**outline字体在GPU上的高保真、可缩放、投影稳定光栅化**。EUI-NEO启发Noir需要真实字体、icon与设计系统；SLUG提供了一个能保持Noir“编译期资源与GPU范围可证明”哲学的高端字体后端。

最正确的战略是：**先建Noir font asset compiler与desktop design token，再把SLUG作为编译器选择的vector-outline backend。** 这样既不会让10,000行日志的正文滚动被复杂fragment计算拖慢，也能让Noir在标题、详情、缩放和3D场景获得真正高质量的字体。

## References

[1]: https://metalbyexample.com/slug/ — Metal by Example, “Slug,” March 30, 2026.

[2]: https://jcgt.org/published/0006/02/02/ — Eric Lengyel, “GPU-Centered Font Rendering Directly from Glyph Outlines,” Journal of Computer Graphics Techniques.

[3]: https://github.com/EricLengyel/Slug — SLUG reference shader implementations and public-domain dedication notice.

[4]: https://terathon.com/i3d2018_lengyel.pdf — Eric Lengyel, i3D 2018 presentation on SLUG’s root classification and coverage approach.
