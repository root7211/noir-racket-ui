# Noir Fontc 与静态 Theme v1 实施报告

**作者：Manus AI**  
**状态：第一阶段完成。**

## 交付范围

本阶段将桌面视觉系统中的两类输入从“示例中散落的常量”收束为可复现构建产物：其一是`noir-fontc`灰度字体atlas/metrics/manifest；其二是`#lang noir/ui`的静态theme token。二者均在构建期执行，不创建运行时theme对象、不增加widget tree、不引入字体shaping/fallback，也没有改写已冻结的列表交互ABI。

| 交付物 | 位置 | 作用 |
|---|---|---|
| `noir-fontc` | `tools/noir_fontc.py` | 确定性TTF/OTF→R8 atlas、PNG、preview与manifest构建器。 |
| 桌面字体spec | `assets/fontc/noir-desktop-sans-18.spec.json` | 18px DejaVu Sans、ASCII printable与日志UI字典的固定coverage输入。 |
| 字体资产 | `out/fontc/noir-desktop-sans-18/` | 95 glyph、512×512 R8 atlas、metrics与SHA-256绑定的manifest。 |
| 静态theme | `noir/ui/main.rkt` | `(theme ...)`、`(theme-color ...)`、`(theme-space ...)`、`(theme-radius ...)`的展开期解析和lowering。 |
| 规格 | `NOIR_FONTC_THEME_ABI_V1.md` | 输入、输出、hash、token、版本和兼容性协议。 |
| 回归 | `tools/verify_fontc_theme.sh` | 字体字节确定性、manifest、theme常量lowering与未知token拒绝。 |

## noir-fontc v1

`noir-fontc`接受严格的`noir-fontc-spec-v1`。font可以是绝对路径或fontconfig family；coverage由`ASCII_PRINTABLE`和固定`extra_text`构成。工具用Pillow渲染单通道mask，用fontTools取得font glyph ID，按升序codepoint和row-major shelf packing分配稳定glyph ID与atlas rect。

首个产物的关键参数如下。

| 属性 | 值 |
|---|---|
| face ID | `noir-desktop-sans-18` |
| renderer kind | `atlas-gray` |
| 字形数 | 95 |
| atlas | 512×512、R8、2px padding |
| metrics | 18px；ascent=17，descent=5，line-height=22 |
| 字体SHA-256 | `ae7b7855e115a5966d8b1b3f80f254ccc117ec86f9965e202ee2940453837280` |
| atlas SHA-256 | `613ac89f108883cfdff0d3e422a2a265120eb4a1c6099803958a102c0fd6956c` |

相同spec被独立执行两次后，`atlas.r8`与`manifest.json`逐字节相同。空白字形以透明、但有固定packing占位的方式处理，避免space造成平台相关或不稳定的atlas布局。

当前fontc产物是**构建期资产与ABI基础**，尚未替换legacy runtime atlas。这样先保证manifest、coverage、metrics、packing和hash契约稳定；下一阶段才将font manifest引用接入Scene/Rust并让新的atlas参与渲染。

## 静态 Theme v1

`theme`只能作为`noir-app`的最多一个顶层声明出现。它包含`color`、`space`、`type`和`radius`四个完整literal section。重复section/token、非法hex、非正数值、未知token或未声明theme时使用token均会在macro expansion阶段被拒绝。

| 声明 | lower结果 | 运行时查找 |
|---|---|---|
| `(theme-color canvas)` | 固定RGBA列表，例如`#0E1117`→`(0.05490 0.06667 0.09020 1.0)` | 无 |
| `(theme-space sm)` | 固定几何值，例如`8` | 无 |
| `(theme-radius panel)` | 固定radius值，例如`14` | 无 |
| `(theme-type body)` | 已验证的静态type token；等待字体renderer接入后作为字号/line box输入 | 无 |

日志浏览器已经正式迁移到`noir-desktop` theme。根surface的canvas、应用栏/列头/detail的surface、append bar的accent以及gap/padding/radius均来自token，但导出的Scene只含既有节点props中的数值RGBA/px，不包含theme map或动态style ID。

## 保持的性能与ABI边界

Visual system v1并未改变下列热路径：

```text
input → compiled task/batch reference → fixed state/GPU write → tile mask + worklist → renderer
```

字体资产构建在运行前完成；theme在Racket macro expansion完成。既有`virtual_list_plan`、`row_activation_plan`、`scrollbar_plan`、`list_navigation_plan`、`log_browser_plan` schema与字段语义均未改变。主题只改变原本已经存在的静态quad颜色、几何常量和日志示例源码表达方式。

## 验证结果

| Oracle | 结果 |
|---|---|
| `tools/verify_fontc_theme.sh` | 通过：95 glyph manifest、双构建字节相等、固定RGBA/radius、未知token拒绝。 |
| `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 通过。 |
| `tools/verify_frozen_list_abi.sh` | 通过。 |
| `tools/verify_log_browser.sh` | 通过：真实X11/Vulkan append、End、ERROR选择、Enter详情、no-packets局部路径及篡改拒绝。 |

## 下一阶段

下一阶段不应直接接入SLUG。应先把`font_manifest_hash`、`face_id`和glyph ID domain作为独立font asset计划写入Scene，并在Rust启动期验证上传资产与manifest一致；随后让灰度atlas作为第二字体后端与当前legacy atlas并存。只有该路径完成黄金图像、DPI与局部tile回归后，才引入SLUG curve/band renderer作为大字、缩放和3D的可选后端。
