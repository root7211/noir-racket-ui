# Dynamic Font Cell Plan v1 — 阶段二交付报告

**作者：Manus AI**
**状态：已实现并完成真实X11/Vulkan验证**

## 结论

`dynamic_font_cell_plan v1` 已将 `noir-table-body-mono-16` 接入 **atlas page 3**，用于两个固定容量虚拟列表的动态正文cell。该路径与page 2静态比例字体完全分离：page 2继续服务标题、列头、按钮和详情chrome；page 3只允许已证明的compact data-register row ring cell改变一个glyph ID word。

> 运行时可变的是已分配cell中的32-bit glyph ID；不可变的是face、atlas page、UV表、10px advance、NDC quad、glyph word地址、tile权限、packet/worklist地址和bind group。

| 维度 | page 2 static proportional | page 3 dynamic tabular |
|---|---|---|
| 资源 | `noir-desktop-sans-18` | `noir-table-body-mono-16` |
| 用途 | 静态desktop chrome | data-register列表正文 |
| 运行时动态性 | 不允许 | 仅glyph ID word |
| atlas page | 2 | 3 |
| glyph domain | 静态manifest域 | `TABULAR_BODY_V1`，37 glyph |
| advance | manifest比例advance | 固定10.0px |
| UV来源 | 每个静态placement | immutable 37-entry GPU UV table |
| Scene合同 | `font_placement_plan v1` | `dynamic_font_cell_plan v1` |

## ABI与编译产物

Scene新增版本化 `dynamic_font_cell_plan` 字段，关闭时为`false`，启用时包含face、R8 manifest/atlas安全相对路径、SHA-256、256×256×1几何、封闭coverage policy、fixed advance和每个table的固定cell权限表。Rust在创建窗口、GPU纹理或bind group之前拒绝不匹配的schema、face、coverage、advance、hash、glyph密度、表格关联、placement slot、glyph word offset、UV和tile权限。

Racket仅在`data-register-table`显式声明 `#:font-face noir-table-body-mono-16` 时迁移该表。未声明face的旧列表继续产生page 1 legacy正文。每个显式tabular row template在宏展开期补齐到register width，使128个日志cell或144个监控cell分别具有一一对应的固定placement和word offset。

WGSL把page 3作为固定binding 5–7的资源：immutable `array<vec4<f32>>` UV表、R8 atlas texture和linear sampler。动态vertex路径读取glyph ID后只在page 3选择预上传UV；fragment路径直接采样page 3 R8覆盖值。shader不做字符串处理、字体查找、fallback、shaping、UV重算或bind group切换。

## 真实验证

| 验证项目 | 结果 |
|---|---|
| Racket语言回归与page-3 Scene导出 | PASS |
| Rust 1.87 / wgpu 30 release | PASS |
| 日志浏览器真实X11/Vulkan截图 | PASS；正文`INFO TIME CORE STARTUP`为tabular灰度字形 |
| 实时监控真实X11/Vulkan截图 | PASS；`WARN ALPHA 042 731 018 012 005`和数值列为tabular灰度字形 |
| page 3 R8 atlas GPU上传 | PASS；65,536 bytes、37 glyph |
| face篡改 | 首帧前拒绝：不支持face/page/coverage/advance策略 |
| UV篡改 | 首帧前拒绝：placement逃逸固定cell proof |
| glyph-word-offset篡改 | 首帧前拒绝：placement逃逸固定cell proof |
| 日志浏览器End → row 9998 → Enter | PASS |
| 监控表格可见性分流 | PASS；3条更新中2条可见，写72 glyph；2条中1条可见，写36 glyph |
| 监控表格纯不可见刷新 | PASS；1条arena-only更新，0 glyph GPU write、0 render request |

视觉审计保存在 `out/DYNAMIC_FONT_CELL_VISUAL_AUDIT.md`，对应截图为 `out/log-browser-page3-tabular.png` 和 `out/realtime-monitor-page3-tabular.png`。

## 性能辅助证据

在 **llvmpipe Vulkan** 下，`coalesced-activate-refresh-telemetry` 完成5次预热与25个GPU timestamp样本。full-redraw中位数为3.076 ms、244个glyph instance；compiler-selected严格执行经proof的coalesced策略，中位数为0.975 ms、48个glyph instance。策略选择的一致性字段确认expected/observed tile mask、draw count、instance count和140-byte winner writes完全一致。

该数字只是当前软件Vulkan适配器上的策略比较。它不构成真实GPU、原生窗口合成或input-to-photon延迟主张。结构化报告和图表分别位于 `out/realtime-monitor-page3-replay-matrix.json` 与 `out/realtime-monitor-page3-replay-matrix.png`。

## 明确边界与下一步

v1只服务有限的等宽表格正文，并拒绝小写、标点、Unicode、比例advance和任意动态run。动态详情、文本编辑和外部内容不得借用page 3权限。下一步可选择扩展第二个**独立且版本化**的动态文本岛，而不能放宽该cell计划；更优先的GUI主线是将正文行的状态色、列对齐和滚动密度基于现有tabular cell继续改善，同时保留此固定地址模型。
