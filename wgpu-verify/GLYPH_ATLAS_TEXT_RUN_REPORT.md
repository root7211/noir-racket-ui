# Noir Glyph Atlas 与 Text-Run 降低验证

## 完成的能力

Noir 的动态文本不再由“数字值映射为颜色”来模拟。现已形成一条真实的 GPU 文本路径：Racket 表面语法中的动态 `text` 在宏展开期降低为固定长度 **`text-run`**；每一个 text-run 分配固定 GPU storage range；wgpu 将 0–9 的位图写入 `R8Unorm` Glyph Atlas 纹理；WGSL 根据 text-run storage 中的 glyph index 生成多个 glyph quad，并采样 atlas 来绘制数字。

```text
(text #:id fps #:dynamic frame-rate #:max-chars 3)
        │
        ▼
text-run { node=fps, state=frame-rate, slots=3, offset=0, bytes=96 }
        │
        ▼
queue.write_buffer(glyph-buffer, 0, three glyph cells)
        │
        ▼
WGSL: 读取 3 个 digit index → 生成 3 个 glyph quad → sample R8 atlas
```

## Racket：从 `text` 到 `text-run`

动态 `text` 的 surface syntax 没有被迫变复杂。宏仍使用最短形式：

```racket
(text #:id fps #:dynamic frame-rate #:max-chars 3)
```

但 `parse-text` 会在 IR properties 中加入：

```racket
'value    '(dynamic frame-rate)
'max-chars 3
'lowering 'text-run
```

动作 IR 也从笼统的 glyph patch 改为显式 `text-run` patch：

```racket
(gpu-update 'text-run 'fps 'frame-rate 0 96 3)
(gpu-update 'text-run 'latency 'latency-ms 96 96 3)
```

`collect-glyph-bindings` 以稳定 Scene tree order 分配 offset；`assert-non-overlapping-bindings!` 在宏展开期检查后一段 offset 不得小于前一段结束位置。因此两个动态节点的区间是语言编译产物，而不是 wgpu host 在运行时猜测得到的结果。

| 动态 text-run | 状态 | Glyph slot | Storage range | Atlas |
|---|---|---:|---:|---|
| `fps` | `frame-rate` | 3 | `[0, 96)` | 数字 `0–9` |
| `latency` | `latency-ms` | 3 | `[96, 192)` | 数字 `0–9` |

## wgpu：Atlas 与 text-run 实例

每一个 glyph cell 保持原有的 32 字节固定预算，但现在第一个 `u32` 是 **atlas glyph index**，而不是供 shader 合成颜色的数值。后端将 3 位整数格式化为零填充文本，例如 `60 → "060"`，并将每个数字的 atlas index 写入对应的 cell。

Atlas 使用单通道 `R8Unorm` texture。host 用程序化 3×5 位图生成 0–9，纹理按 10 个 6×8 cell 横向排列。它是真实纹理资源，使用 nearest sampler；每个 text-run glyph 在 vertex stage 计算 atlas UV，fragment stage 使用 `textureSample` 的 coverage 值绘制金色数字笔画。

```wgsl
let digit = glyph_words[glyph_word_offset + glyph_index * 8u];
let atlas_px = vec2<f32>(f32(digit) * 6.0 + 1.0, 1.0)
             + unit * vec2<f32>(3.0, 5.0);
output.uv = atlas_px / vec2<f32>(60.0, 8.0);

let coverage = textureSample(digit_atlas, atlas_sampler, input.uv).r;
return vec4<f32>(gold.rgb, gold.a * coverage);
```

## 实测验证

在 wgpu 0.20.1、Vulkan backend 和 llvmpipe CPU adapter 上，程序完成 device 初始化、storage buffer 写入、atlas texture 上传、bind group 创建、WGSL pipeline 创建、离屏渲染与 map readback。

```text
Noir Glyph Atlas → wgpu text-run isolation verification
  scene nodes     : 8
  instance budget : 8 (used 8)
  text-run glyph budget: 6
  global text-run steps : 2
  exact bindings  : [("fps", 0, 96), ("latency", 96, 96)]

  action refresh-fps
    gpu writes  : [(0, 96)]
    state       : {frame-rate: 144, latency-ms: 8}
    checksum    : 30052419 → 29780069

  action refresh-latency
    gpu writes  : [(96, 96)]
    state       : {frame-rate: 144, latency-ms: 15}
    checksum    : 29780069 → 29630486

  shared pipelines : 1
```

三个离屏回读帧中的数字是 atlas 采样结果，而不是色块：

| 基线：`060` / `008` | FPS 后：`144` / `008` | 延迟后：`144` / `015` |
|---|---|---|
| ![baseline](out/noir-atlas-baseline.png) | ![fps](out/noir-atlas-refresh-fps.png) | ![latency](out/noir-atlas-refresh-latency.png) |

第一条 action 后，前三个 glyph quad 的输入 storage 从 `[0,96)` 读取新数据，后三区间仍保持 `008`。第二条 action 后，后三区间 `[96,192)` 变化为 `015`，而 FPS text-run 保持 `144`。两次动作都没有改写 instance buffer 或创建新 pipeline。

## 仍然受限的部分

这是一个可审计的**数字 text-run MVP**，不含 Unicode shaping、kerning、line breaking、fallback font 或真实字体文件解析。它故意将范围限制为固定长度、等宽的数字，以先验证 noir 最重要的机制：**文本变化也能遵守编译期确定的局部 GPU 写入边界。**

下一阶段可将程序化数字 atlas 替换为预烘焙 MSDF/SDF atlas，并将 glyph cell 扩展为 atlas UV、advance、颜色和 transform；`offset + byte_length`、动作因果图和 buffer-range 隔离不需要改变。
