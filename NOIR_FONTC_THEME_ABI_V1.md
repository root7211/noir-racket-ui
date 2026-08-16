# Noir Fontc 与静态 Theme ABI v1

## 范围

本ABI定义两项纯构建期产物：`noir-fontc`的字体资产manifest和`#lang noir/ui`的静态theme token。它们不修改既有virtual-list、row activation、scrollbar、navigation或log-browser ABI。

## noir-fontc v1

### 输入

`noir-fontc`接受一个确定性JSON spec：

```json
{
  "schema": "noir-fontc-spec-v1",
  "face_id": "noir-desktop-sans-18",
  "font": "/absolute/or/project-relative/font.ttf",
  "pixel_size": 18,
  "charset": "ASCII_PRINTABLE",
  "extra_text": ["SYSTEM LOG BROWSER", "LEVEL", "TIME", "SOURCE", "MESSAGE"],
  "atlas": {"width": 512, "height": 512, "padding": 2, "mode": "gray"}
}
```

输入文本仅用于构建期coverage扩展；`ASCII_PRINTABLE`与`extra_text`共同决定静态chrome允许glyph domain。v1还定义第二个封闭值`TABULAR_BODY_V1`：它固定为`SPACE + 0–9 + A–Z`，不得携带`extra_text`，并必须声明`advance_policy: "fixed-tabular"`与正数`fixed_advance`。任何字体文件、字号、coverage、advance policy或packing参数变更都必须生成新的manifest hash。

`TABULAR_BODY_V1`仅生成受限资产，并不自动授予运行时动态文本权限；其page-3消费必须等待独立的`dynamic_font_cell_plan v1`准入。

### 输出

一个fontc产物目录包含：

| 文件 | 内容 |
|---|---|
| `atlas.png` | 单通道灰度glyph atlas；PNG只用于审计/离线检查。 |
| `atlas.r8` | 严格的row-major 8-bit GPU上传字节。 |
| `manifest.json` | schema、face ID、font sha256、atlas sha256、metrics与glyph表。 |
| `preview.png` | 由fontc生成的coverage/packing视觉检查页。 |

`manifest.json`必须含：

```json
{
  "schema": "noir-font-asset-manifest-v1",
  "revision": 1,
  "face_id": "noir-desktop-sans-18",
  "renderer_kind": "atlas-gray",
  "font_sha256": "...",
  "atlas_sha256": "...",
  "atlas": {"width": 512, "height": 512, "channels": 1, "padding": 2},
  "metrics": {"ascent": 17, "descent": 5, "line_height": 22},
  "glyphs": [
    {"codepoint": 65, "glyph_id": 0, "x": 2, "y": 2, "width": 13, "height": 14,
     "advance": 13.0, "bearing_x": 0.0, "bearing_y": 14.0}
  ]
}
```

Glyph ID根据升序Unicode codepoint稳定分配。packing使用确定性row-major shelf策略；同一输入必须得到字节一致的R8、JSON和preview。fontc拒绝atlas容量不足、重复字符或缺失glyph。对于`fixed-tabular`，manifest附加`coverage_policy`、`advance_policy`、`fixed_advance`和每glyph的审计性`source_advance`；运行时布局未来只能读取统一的`advance`，不得使用`source_advance`重新排版。

### 启动期准入

未来Rust Scene ABI只接受显式列出的`font_manifest_hash`、`face_id`与glyph ID range。宿主必须验证atlas/manifest SHA-256、glyph ID合法性、placement UV落在manifest atlas内以及每个glyph属于已经lower的静态coverage。v1中fontc产物生成并验证，但尚不替换当前legacy atlas renderer。

## 静态 Theme v1

### 声明

```racket
(theme noir-desktop
  (color canvas "#0E1117" surface "#171B24" text "#F4F7FB" accent "#4C8DFF")
  (space xs 4 sm 8 md 12 lg 16 xl 24 page 32)
  (type caption 13 body 15 label 16 title 28 display 36)
  (radius control 6 card 10 panel 14 overlay 18))
```

`theme`只能出现在`noir-app`之前的模块顶层。所有名称和值是字面量；重复token、非正尺寸、未知hex、非RGBA颜色或不成对的name/value都会在expand期失败。

### Lowering

主题不进入Scene状态表。`theme-color`、`theme-space`、`theme-type`、`theme-radius`在宏expand时直接替换为固定常量：

| 使用位置 | lower结果 |
|---|---|
| `#:background (theme-color surface)` | 编译期RGBA列表 |
| `#:padding (theme-space lg)` | 固定px几何 |
| `#:font-size (theme-type body)` | 固定font size/line box输入 |
| `#:radius (theme-radius card)` | 固定quad field或shader variant输入 |

Theme v1提供编译期符号解析及可审计导出，不产生运行时hash-map、动态查找或theme切换分支。

## 兼容性与版本规则

`noir-fontc-spec-v1`、`noir-font-asset-manifest-v1`和`noir-static-theme-v1`均独立版本化。既有必填字段和既有`ASCII_PRINTABLE`语义不得改写；仅构建审计用的可选描述字段可后向兼容地加入manifest。任何会改变Scene资源选择、GPU page、cell写权限或运行时解释的语义，必须新建独立Scene ABI；`TABULAR_BODY_V1`后续消费即为`dynamic_font_cell_plan v1`。未启用theme的既有Noir fixture继续以原始literal颜色和几何编译，从而保持现有Scene ABI兼容。
