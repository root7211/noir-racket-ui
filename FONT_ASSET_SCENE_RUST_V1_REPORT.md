# Font Asset Scene / Rust Integration v1

**作者：Manus AI**

## 交付结论

Noir 第二阶段已将 `noir-fontc` 的字体资源从构建期文件接入版本化 Scene，并在 Rust/wgpu 宿主中完成严格启动期验证与GPU注册。`noir-desktop-sans-18` 现在作为 `face_id=noir-desktop-sans-18`、`atlas_page=2` 的独立灰度 R8 资源出现于日志浏览器 Scene；它不改变既有 page 0/1 legacy atlas，也未改变任何虚拟列表、action、tile、worklist 或 glyph placement ABI。

> v1 的资源状态是 **`registered-inactive`**：atlas 已通过manifest proof并上传到GPU，但现有legacy placement还没有fontc的比例metrics/UV。因此宿主故意不让旧 placement 采样新atlas，避免以“看似接入”换取错误文字渲染。

| 接口层 | 实现 | 运行时边界 |
|---|---|---|
| Racket | `(font-asset #:manifest "assets/.../manifest.json" #:atlas "assets/.../atlas.r8")` | 宏展开期读取manifest、验证R8长度和dense glyph domain。 |
| Scene | `abi_contracts.font_asset_plan` + `font_assets[]` | 导出face ID、hash、像素规格、domain、page与activation。 |
| Rust proof | `compiler_font_assets` | 校验schema、路径安全、manifest一致性、SHA-256、长度、连续glyph ID与page隔离。 |
| wgpu | `make_registered_font_atlases` | 创建不可变 `R8Unorm` 2D texture并完整上传262,144字节。 |
| 兼容性 | legacy page 0/1继续使用 | 所有已有列表、日志和交互路径保留既有采样器与glyph placement。 |

## ABI 与资源证据

正式接口为 [`FONT_ASSET_PLAN_ABI_V1.md`](FONT_ASSET_PLAN_ABI_V1.md)。实际资产位于：

```text
assets/fontc/noir-desktop-sans-18/
├── manifest.json
├── atlas.r8
└── preview.png
```

实际资源的关键常量如下。

| 字段 | 值 |
|---|---|
| ABI | `noir-font-asset-plan-v1@1` |
| face ID | `noir-desktop-sans-18` |
| renderer kind | `atlas-gray` |
| atlas | 512 × 512 × 1, `R8Unorm` |
| glyph domain | `0..94`，共95个连续glyph ID |
| isolated atlas page | `2` |
| activation | `registered-inactive` |
| R8 atlas SHA-256 | `613ac89f108883cfdff0d3e422a2a265120eb4a1c6099803958a102c0fd6956c` |

Rust使用 `sha2` 对读取到的真实R8字节重新计算SHA-256，而不是信任Scene或manifest声明。路径必须为无 `..`、非绝对的相对路径；Scene位于`out/`时，宿主按Scene目录与其项目根回退目录解析资产，以支持标准导出布局但不允许路径逃逸。

## 真实验证

`tools/verify_font_asset_scene.sh` 在真实 X11/Vulkan/wgpu 30 release宿主中执行以下oracle。

| 验证 | 结果 |
|---|---|
| Racket Scene导出与全量回归 | 通过 |
| `verify_fontc_theme.sh` | 通过 |
| release宿主的font asset proof | 通过 |
| 真实R8 atlas GPU上传 | 通过；日志确认`bytes=262144`和预期hash |
| 篡改atlas第一个字节 | 在启动期拒绝：`atlas SHA-256 mismatch` |
| 将page 2篡改为page 1 | 在启动期拒绝：`must own isolated atlas page 2` |

正向日志在创建Host时显示：

```text
compiler font asset: face=noir-desktop-sans-18 page=2 glyphs=95 atlas=512x512 r8 activation=registered-inactive
font-atlas-upload: face=noir-desktop-sans-18 page=2 bytes=262144 sha256=613a… renderer=registered-inactive
```

## 未做与下一阶段

本阶段没有实现runtime shaping、fallback、比例glyph placement重lower或将page 2绑定到现有`host_placement.wgsl`。这些都是刻意保留的下一阶段工作：Racket为选定静态text-run输出`face_id`、fontc UV和比例advance；Rust为新增placement域建立第二glyph sampler/bind group；启动期proof随后验证每个page-2 placement的glyph domain与UV矩形。完成之后，Noir可以先让应用栏、标题、列头和详情使用灰度比例字体，而10,000行滚动正文暂时仍使用legacy/MSDF类高吞吐路径。

这一顺序保持Noir核心原则：字体质量提升是**编译期资产与固定GPU范围**的扩展，而不是把字体测量、layout或atlas重建塞入交互热路径。
