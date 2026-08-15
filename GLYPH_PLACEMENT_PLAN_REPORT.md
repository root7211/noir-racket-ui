# Noir Glyph Placement Plan：编译期逐字形几何与 Draw Packet

**作者：Manus AI**  
**实现范围：** `#lang noir/ui` 的 Racket 宏前端、Scene runtime IR、Scene JSON lowering 与编译期回归 oracle。  
**目标：** 将文本从“已 shape 的 glyph run”进一步降低为**逐 glyph 的固定几何 placement**与**按 atlas page/clip/z/batch 划分的 Draw Packet**，使后端不再根据 `glyph_count`、字符串或父布局推导字形位置、atlas cell 和绘制分组。

> 本阶段的核心性质是：**glyph 内容可以是动态的，但 glyph placement 绝不动态。** 对动态数字，action 未来只需覆写预分配 glyph cell 的首个 `u32 glyph_id`；它不能改变 quad 的 NDC 坐标、大小、atlas page、clip stack、z-order 或 batch membership。

## 1. 产物边界

此前的 Text Shaping 已将静态标题变为 page-1 glyph ID，并给动态数字固定分配了 page-0 glyph storage range。但 text-run shader 仍能够从 `glyph_count` 推导等宽 glyph 的位置。本阶段将该派生步骤移入 macro expansion。

| 层次 | 之前 | Glyph Placement Plan 之后 |
|---|---|---|
| 静态标题内容 | 编译期 glyph IDs | 编译期 glyph IDs，不变 |
| glyph storage 地址 | 编译期 range | **逐 glyph 固定 byte/word offset** |
| glyph 位置 | shader 根据 run 的 `size/glyph_count` 推导 | **编译期固定 `ndc_pos` / `ndc_size`** |
| Atlas 坐标 | shader 根据 glyph ID 推导 cell | **编译期固定 `atlas_uv` rect** |
| clip/z/batch | 文本仅隐式继承实例语义 | **逐 glyph 显式携带 compiler 的 clip/z/batch 语义** |
| draw 合并 | 后端自行扫描 text-run | **Draw Packet 是 compiler 输出的连续 range** |

这不是把文本转为不可变图像。静态标题仍以 atlas glyph 绘制，动态数字仍使用相同 storage buffer；变化在于运行时不再拥有关于“文本如何布局”的决策权。

## 2. 新增 Runtime Scene IR

`noir/ui/main.rkt` 扩展 `scene` 结构，在既有 `layout-plan` 后增加两个一等字段：

```racket
(struct scene
  (root static-node-count dynamic-node-count resource-budget state actions
        update-plan layout-plan glyph-placement-plan glyph-draw-packets
        event-map animation-tracks frame-schedule conflict-graph render-schedules)
  #:transparent)
```

逐 glyph 记录的 runtime 结构为：

```racket
(struct glyph-placement
  (slot node glyph-index glyph-id atlas-page glyph-byte-offset glyph-word-offset
        ndc-pos ndc-size atlas-uv advance dynamic? state
        clip-stack-id clip-rect z-layer batch-key)
  #:transparent)
```

| 字段 | 编译期来源 | 后端含义 |
|---|---|---|
| `slot` | glyph binding 的稳定 DFS range | 32-byte glyph cell 序号 |
| `glyph-id` | 静态 ASCII shaping 或动态 state 的 initial digits | `(page << 16) | atlas_cell` |
| `glyph-byte-offset` / `glyph-word-offset` | `slot × 32`、`byte_offset / 4` | storage buffer 的固定定位地址 |
| `ndc-pos` / `ndc-size` | Layout Plan + advance prefix sum | 直接可绘制的 glyph quad |
| `atlas-uv` | glyph ID 低 16 位和固定 162×8 atlas | cell 内 3×5 bitmap UV rect |
| `dynamic?` / `state` | `#:dynamic` binding | 表示 action 可更改该 cell 的 glyph ID |
| `clip-stack-id` / `clip-rect` / `z-layer` / `batch-key` | 既有 `compile-composites` | 让文本复用 Render Schedule 的静态合成语义 |

Draw Packet 结构只压缩**兼容且连续**的 placement；它不隐藏任何 runtime 判定：

```racket
(struct glyph-draw-packet
  (id atlas-page first-placement placement-count
      first-glyph-byte-offset glyph-byte-length nodes
      clip-stack-id clip-rect z-layer batch-key dynamic?)
  #:transparent)
```

Packet 的兼容条件是：连续 slot、相同 atlas page、相同 clip stack/rect、相同 z、相同 batch key，且同为 static 或 dynamic。这样静态 page-1 title 不会和 page-0 数字混合；同页且 geometry range 连续的 `fps` 与 `latency` 则可形成一个 page-0 dynamic packet。

## 3. 动态数字的首帧 lowering

`shape-initial-digits` 是新增的 expand-time 函数。它从声明的状态初值和 `#:max-chars` 生成固定宽度的 page-0 glyph ID。其职责只限于**首帧**：例如 `frame-rate = 60` 与 3 个 slot 降低为 `'(0 6 0)`，`latency-ms = 8` 降低为 `'(0 0 8)`。

```racket
(define (shape-initial-digits who state-id initial glyph-count source)
  (unless (exact-nonnegative-integer? initial)
    (raise-syntax-error who "dynamic numeric text needs a non-negative initial value" source))
  (define raw (number->string initial))
  (when (> (string-length raw) glyph-count)
    (raise-syntax-error who "initial value exceeds fixed glyph capacity" source))
  (define padded
    (string-append (make-string (- glyph-count (string-length raw)) #\0) raw))
  (map (lambda (ch)
         (encode-glyph digit-atlas-page
                       (- (char->integer ch) (char->integer #\0))))
       (string->list padded)))
```

action 路径不重新执行该函数。它保持既有 `gpu_update` 的固定 range；下一阶段的 12-byte 优化可以直接依赖 Placement Plan 的 3 个预定义 `glyph-byte-offset`，将当前全 cell 更新替换为三个 4-byte ID 写入。

## 4. 编译期 placement lowering 算法

`compile-glyph-placement-plan` 接收 root AST、state 声明和现有 Layout Plan。其算法有四步。

首先，编译器构造 `binding-by-id`、`layout-by-id`、`initial-state-by-id` 和 `composite-by-id`。其中 `composite-by-id` 明确复用已有 `compile-composites` 的 clip stack、有效 clip rect、z layer 与合成顺序；文本不存在第二套独立的裁剪或排序规则。

其次，针对每个 text binding，静态 binding 取 `shape-static-ascii` 生成的 page-1 IDs；动态 binding 取 `shape-initial-digits` 生成的 page-0 首帧 IDs。编译器验证 glyph ID 数量与 advance 数量严格相同，并验证 advance 总和为正数。

然后，宏展开期进行 advance 前缀和。对于第 `i` 个 glyph，`glyph-byte-offset = binding.offset + i × 32`，而 NDC quad 根据 text layout rect 和所有前导 advance 直接计算。当前 3×5 等宽字体的每个 advance 都为 `1.0`，但接口并未把这一事实编码为运行时假设：非等宽字体可直接由 compiler 提供不同的 advance 列表。

```racket
(define unit-advance (/ (first run-size) total-advance))
(define glyph-pos
  (list (+ start-x (* prefix unit-advance))
        (+ (second run-pos) (* (second run-size) 0.19))))
(define glyph-size
  (list (* unit-advance advance 0.58)
        (* (second run-size) 0.62)))
```

最后，compiler 将相邻 placement 归并为 packet。packet ID、page、首 slot、长度、byte range、node list、clip/z/batch 与 dynamic 属性全部是 expand-time 常量。

## 5. 固定 Atlas UV 计算

两个 atlas page 都使用 `162×8` 的 `R8Unorm` 纹理层，且 cell 固定为 `6×8` 像素，真实 3×5 点阵在 cell 的 `(1,1)` 开始。glyph ID 的高 16 位已被 atlas page 消费，低 16 位则给出 cell index。

```racket
(define (atlas-uv glyph-id)
  (define glyph-index (bitwise-and glyph-id #xffff))
  (list (/ (+ (* glyph-index 6.0) 1.0) 162.0)
        (/ 1.0 8.0)
        (/ 3.0 162.0)
        (/ 5.0 8.0)))
```

这使 `atlas_uv` 成为不依赖 shader glyph-index 分支的确定性 compiler 产物。下游 shader 可以直接使用该 rect；保留 `glyph_id` 只是为了兼容现有 storage ABI 与动态内容覆盖。

## 6. 编译期不变量

`assert-glyph-placement-plan!` 在宏展开期拒绝以下情况：placement slot 非连续、byte offset 与 slot 不一致、word offset 与 byte offset 不一致、glyph ID 高 16 位与 atlas page 不一致、packet 的 coverage 非连续，以及 packet byte length 不是完整 32-byte cell 的整数倍。

| 不变量 | 公式 | 防止的运行时问题 |
|---|---|---|
| Dense slots | `placement.slot = 0..N-1` | host 对 glyph range 的二次寻址 |
| Cell alignment | `byte_offset = slot × 32` | storage cell 部分覆盖或 ABI 漂移 |
| Word address | `word_offset = byte_offset / 4` | WGSL storage 访问错位 |
| Page encoding | `glyph_id >> 16 = atlas_page` | 采样错误 atlas layer |
| Packet coverage | `packet.first = previous.first + previous.count` | 漏绘或重复绘制 |
| Packet size | `byte_length = count × 32` | 运行时无法安全映射写入区间 |

这些性质在 Racket 编译期成立，不由 wgpu host 的容错逻辑“补救”。

## 7. Dashboard 编译结果

`dashboard.rkt` 产生 31 个 glyph placement、2 个 packets：

| Packet | Page | Placement slots | Storage range | Nodes | Dynamic |
|---|---:|---:|---:|---|---|
| `glyph-packet-page1-slot0-24` | 1 | 0–24 | `[0,800)` | `title` | 否 |
| `glyph-packet-page0-slot25-30` | 0 | 25–30 | `[800,992)` | `fps`, `latency` | 是 |

静态标题的第一个 `N` placement 使用：

```text
slot                 = 0
glyph_id             = 65550 = 0x0001_000E
atlas_page           = 1
glyph_byte_offset    = 0
glyph_word_offset    = 0
atlas_uv             = [85/162, 1/8, 3/162, 5/8]
dynamic              = false
```

动态 FPS 初值 `060` 占用 slots 25–27；latency 初值 `008` 占用 slots 28–30。二者虽然合并为同一 dynamic page-0 packet，但仍保留各自 node/state 字段，未来 action 可只写自己所属的三个 ID slot。

## 8. Scene JSON ABI

`scene->jsexpr` 已输出两个新顶层字段：

```json
{
  "glyph_placement_plan": [
    {
      "slot": 0,
      "node": "title",
      "glyph_id": 65550,
      "atlas_page": 1,
      "glyph_byte_offset": 0,
      "glyph_word_offset": 0,
      "ndc_pos": ["...", "..."],
      "ndc_size": ["...", "..."],
      "atlas_uv": [0.524691..., 0.125, 0.018518..., 0.625],
      "dynamic": false,
      "clip_stack_id": "root",
      "z_layer": 0,
      "batch_key": "glyph-atlas|page:1|clip:root|blend:alpha"
    }
  ],
  "glyph_draw_packets": ["..."]
}
```

其中示意中的 `"..."` 仅表示与具体 layout 有关的数值；真实 `out/glyph-placement.scene.json` 包含全部数字。`compile-scene->wgpu-plan` 同步公开 `glyph-placement-plan` 与 `glyph-draw-packets`，因此 Rust/Nelua/C 后端均可直接消费同一编译产物。

## 9. 验证

| 验证 | 命令/方法 | 结果 |
|---|---|---|
| Placement compiler oracle | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 通过：31 dense placement、静态 page-1 UV、动态 `060`/`008` 初值、2 个 packet 均被断言 |
| JSON 导出 | `racket tools/export-dashboard.rkt out/glyph-placement.scene.json` | 通过：新 JSON 含 `glyph_placement_plan` 和 `glyph_draw_packets` |
| Rust release build | 既有 `noir_winit_host` release binary | 可用；新增 JSON 字段保持后向兼容 |
| 真实 GPU/X11 回归 | `./tools/verify_winit_host.sh out/glyph-placement.scene.json` | 通过：Vulkan/llvmpipe + Xvfb + `xdotool` 三按钮事件闭环 |
| 精确局部写入 | 验证脚本日志 oracle | `fps=[800,896)`、`latency=[896,992)`、`progress=[316,320)`，均未被 Placement 元数据改变 |

真实 X11 验证日志确认静态 shaped run 已加载，并保持既有最短 action path：

```text
compiler text resources: 1 static shaped run(s), 2 dynamic text-run action(s)
glyph-patch fps: [800..896)
glyph-patch latency: [896..992)
instance-patch progress: [316..320)
winit host multi-page Glyph Atlas + static shaping + Event Map roundtrip verified.
```

## 10. 可复现实验

在 `noir-racket-ui` 中执行：

```bash
PLTCOLLECTS="$PWD:" racket tests/run.rkt

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/glyph-placement.scene.json

./tools/verify_winit_host.sh out/glyph-placement.scene.json
```

## 11. 后续后端接入建议

本阶段已经输出了后端可直接使用的逐 glyph quad，但当前 winit host 仍使用旧 text-run shader，因而仅把新增 JSON 视为兼容的未来字段。下一步应将 `glyph-placement-plan` 上传为一块独立、只读的 placement vertex/storage buffer，并按 `glyph-draw-packets` 绑定 page-aware pipeline。届时静态文本 shader 可删除 `glyph_count` 除法、`vertex_index / 6` 的 run-indexing 及内部 glyph placement；动态 action 则可从 96-byte cell payload 更新进一步压缩为每 glyph 一个 4-byte glyph ID 写入。

> 结论：Glyph Placement Plan 已把**文本的几何、UV、GPU cell 地址、page、clip、z 与 batch 归属**全部变成 Racket 宏展开期可审计数据。当前 wgpu host 仍保持兼容运行；后续仅需消费该新 ABI，即可删除文本路径最后一段由运行时派生的 layout 工作。
