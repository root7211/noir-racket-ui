# Noir Tabular Body Font Asset v1

**状态：第一阶段已完成；尚未注册或采样到GPU page 3。**

## 1. 目的与边界

`noir-table-body-mono-16` 是为数据密集型固定容量列表准备的**受限表格正文face**。它解决视觉语言v1留下的一个明确问题：标题与列头已经使用比例灰度字体，但动态行正文仍使用5×7 legacy atlas。

该资产不是任意动态文本方案。它不支持运行时字体查询、Unicode shaping、fallback、可变字符串长度、kerning或逐run重新布局。其唯一目标是使已经具备固定cell地址、固定row template、固定capacity和固定data-register宽度的列表正文获得更高质量的等宽灰度字形。

## 2. Asset 规格

| 字段 | 值 |
|---|---|
| face ID | `noir-table-body-mono-16` |
| 设计字体 | DejaVu Sans Mono |
| 像素大小 | 16 px |
| atlas | 256×256、R8、padding 2 |
| renderer kind | `atlas-gray` |
| coverage policy | `tabular-body-v1` |
| advance policy | `fixed-tabular` |
| fixed advance | 10.0 px |
| glyph count | 37 |
| 产物目录 | `assets/fontc/noir-table-body-mono-16/` |

## 3. 封闭 glyph domain

字符按Unicode codepoint升序分配dense glyph ID，运行时不参与映射。

```text
SPACE (U+0020)
0–9   (U+0030–U+0039)
A–Z   (U+0041–U+005A)
```

这正好覆盖当前日志浏览器与实时监控表格的动态正文：状态词、主机/来源代号、固定英文标签、空格和数值列。任何小写字母、连字符、标点或非ASCII文本均不属于该face；其写入必须在未来的page-3启动期proof中拒绝，而不是悄然回退到任意atlas页。

`TABULAR_BODY_V1` 在fontc输入层是封闭域。spec不得携带`extra_text`，因此构建者不能不经ABI变更就扩展动态可写字符空间。

## 4. Manifest 不变量

`manifest.json` 继续使用 `noir-font-asset-manifest-v1@1`，并增加后向兼容的描述字段：

| 字段 | 约束 |
|---|---|
| `coverage_policy` | 必须为`tabular-body-v1` |
| `advance_policy` | 必须为`fixed-tabular` |
| `fixed_advance` | 必须为10.0 |
| `glyph_count` | 必须为37 |
| `glyph_id` | 0–36连续且与codepoint升序一一对应 |
| `glyph.advance` | 每个glyph均为10.0 |
| `glyph.source_advance` | 保留字体原始advance，仅作构建审计；不得被运行时布局读取 |
| `atlas_sha256` | 必须匹配`atlas.r8`完整字节 |

## 5. 后续 page-3 接入契约

第二阶段不得复用`font_placement_plan v1`的page-2静态比例文本语义。必须新建独立的 `dynamic_font_cell_plan v1`，至少固定：

1. `face_id=noir-table-body-mono-16`、`atlas_page=3`、manifest/atlas SHA-256与37-glyph domain；
2. 每个允许的data-register table、row ring slot、cell index和glyph-word offset；
3. 每个cell的固定10px advance、NDC quad、baseline、UV真值与tile/worklist归属；
4. “只写glyph ID word”的运行时更新权限，禁止改写page、UV、advance、face、geometry、clip或resource binding；
5. 非本domain字符、非准入slot、page-3 static placement和page-2 dynamic placement均必须在首帧前拒绝。

因此未来数据流仍然是：

> `data-update-batch → compiler-proved page-3 cell-word patch → visible-row tile/worklist → renderer`

而不是运行时shape、font lookup或layout。

## 6. 可复现构建

```bash
cd /home/ubuntu/noir_review/noir-racket-ui-statistical-analysis
./tools/verify_tabular_body_font.sh
```

该回归二次编译并逐字节比较atlas、manifest、preview和PNG；验证37-glyph dense domain、10px固定advance、日志/监控正文语料覆盖，并拒绝通过`extra_text`扩大封闭字符域的输入攻击。
