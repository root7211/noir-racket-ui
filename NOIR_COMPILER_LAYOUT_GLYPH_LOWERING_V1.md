# `noir-compiler` Layout and Glyph Summary Lowering v1

## 目标

第二个Rust lowering pass在已有profile语义计划上加入**静态布局约束**与**glyph布局摘要**。它证明Rust能从同一闭合应用输入重建关键几何端点和可审计字形预算，同时不虚假声称已取代Racket完整布局器、font compiler或GPU地址分配器。

## 输入与输出

输入沿用首个pass的`ApplicationInput`：稳定应用ID、`standard | compact` profile，以及隐含的Alerts `acknowledged`行状态域。输出为`ProfileLayoutGlyphProjection`，由以下四部分组成：

| 投影 | Rust负责的内容 | Racket仍负责的内容 |
|---|---|---|
| Canvas | `1280 × 720`静态画布约束 | 任意未来窗口适配策略。 |
| Key rectangles | rail、Overview/Systems/Alerts resident view、两个虚拟列表viewport、Overview确认计数端点。 | 其他全部组件的完整树与每个surface实例地址。 |
| Glyph summary | placement总数、动态placement数、face/page集合、确认计数8 glyph范围。 | 每一个glyph的UV、advance、clip、NDC和buffer地址。 |
| Composition | profile语义计划与上述约束的一致性。 | 完整render schedule、tile和GPU pipeline。 |

## 冻结端点

所有profile共享画布、rail、三视图和确认计数矩形。双arena容量驱动其viewport行数：标准Systems为4行（高128 px）、Alerts为3行（高96 px）；compact两者均为3行（高96 px）。

| Endpoint | 矩形 `x, y, w, h` |
|---|---|
| Rail | `32, 32, 180, 656` |
| Resident view | `236, 104, 996, 560` |
| Systems viewport | `256, 182, 956, profile-derived` |
| Alerts viewport | `256, 182, 956, 96` |
| Overview acknowledged count | `260, 228, 238, 40`，8个固定glyph |

标准profile glyph摘要为总`487`、动态`290`、确认计数首字节`2464`；compact为总`463`、动态`258`、确认计数首字节`2720`。两个profile的glyph stride都固定为32 bytes，非空face集合为`noir-desktop-sans-18`与`noir-table-body-mono-16`，atlas page集合为`1, 2, 3`。确认计数的八个动态page-1 glyph在Racket完整Scene中`face_id`为JSON `null`；所以端点ABI也冻结为Rust `None`，而不伪造为desktop-sans。该端点仍严格证明其节点、矩形、8 glyph计数、首末字节、32-byte stride和atlas page。

## 非目标

v1不lower任意flex/grid约束、文本塑形、UV坐标、font atlas、完整placement、scissor/tile、instance/glyph缓冲偏移或实际GPU资源。Racket继续是这些完整Scene细节的唯一生产者；Rust输出仅作为下一步迁移布局与字形资源的可差分几何摘要合同。
