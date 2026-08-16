# Page-2 Static Font Baseline Fix v1

## 结论

已修复 Noir page-2 比例字体的小写字母垂直placement。最终问题既不在字体文件、atlas UV、GPU shader，也不在Material token；根因是Racket编译器没有把 Pillow glyph bounding box 正确映射到 WGSL 所要求的 **lower-left glyph quad** 坐标。

`fontc`保存 `bearing_y = -bbox.top`、`height = bbox.bottom - bbox.top`。glyph placement shader则将 `GlyphPlacementInstance.ndc_pos` 解释为quad的lower-left。因此，正确的固定偏移必须是：

```text
quad_lower_left_y = shared_line_anchor_y
                    − (glyph_height − bearing_y) × line_scale
```

其中 `glyph_height − bearing_y` 精确等于 Pillow 的 `bbox.bottom`。这使所有非下伸字母共享quad lower edge（排版baseline），并让 `g/j/p/q/y`按各自更大的`bbox.bottom`自然延伸到baseline下方。

> 早先的“修复”遗漏了glyph height，错误地把glyph整体推到文本行上方；该公式已被撤销，未提交或发布。

## 根因与最终修复

| 项目 | 错误实现 | 最终实现 |
|---|---|---|
| 坐标参考 | 把glyph top/bearing与NDC lower-left混淆。 | 以WGSL `pos`为glyph quad lower-left。 |
| 应用的度量 | 在run项和glyph项重复使用`bearing_y`，或遗漏`height`。 | 只使用一次`bbox.bottom = height − bearing_y`。 |
| 非下伸字母 | 可能强制顶边相同，或整体上移。 | `a/e/c/i/l/h/S/t`的quad lower edge相等。 |
| descender | 无法从常规小写中区分。 | `g/j/p/q/y`因更大的bbox bottom向下延伸。 |
| 运行时成本 | 不适用。 | 不增加：仍只消费编译期写入的placement。 |

## 结构不变量

`tests/run.rkt`新增真实fixture检查：`material-summary-title`的`"Service health"`包含一个空格和全部非下伸字母。对每一个非空白placement，`GlyphPlacementInstance.ndc_pos.y`必须在`1e-10`内相同。该条件符合shader的lower-left约定，直接保护共同baseline，而非误把不同高度glyph的顶部或上边界设为相同。

本修复没有改变任何运行时ABI或字体资源：

| 契约 | 状态 |
|---|---|
| page-2 manifest、atlas bytes与SHA-256 | 不变。 |
| `GlyphPlacementInstance` 48-byte GPU ABI | 不变。 |
| glyph ID、atlas page、UV、advance、packet与storage offset | 不变。 |
| `rounded_surface_plan`、action slot、tile/worklist ABI | 不变。 |
| host/WGSL运行时分支与buffer写入 | 不变。 |

## 验证

以下验证均在最终公式下通过：

| 验证入口 | 结果 |
|---|---|
| `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 通过，含共同lower-edge baseline oracle。 |
| `bash tools/verify_font_placement_scene.sh` | 通过。 |
| `bash tools/verify_material_profile_v1.sh` | 通过：Scene oracle、宏输入拒绝、Rust 1.87/wgpu 30、真实X11/Vulkan、button action与glyph patch。 |
| `bash tools/verify_rounded_surface_plan.sh` | 通过：双应用Scene oracle、四类篡改拒绝与真实交互。 |

[`out/material-profile-dashboard-v1.png`](out/material-profile-dashboard-v1.png) 是最终公式下的真实X11/Vulkan帧。开发期间的前后审阅板由 [`tools/make_font_baseline_comparison.py`](tools/make_font_baseline_comparison.py)生成；它对照已发布的错误顶边版本与最终真实输出，但不构成额外运行时资产。

## 范围

本次仅修复 **page-2静态比例字体** 的垂直placement。page-3动态tabular body采用独立的固定16px cell lowering，未作改动。字体hinting、gamma/SDF质量、字距、kerning、复杂脚本shaping与动态字体域仍属于独立问题，不应以修改baseline公式的方式混入本次修复。
