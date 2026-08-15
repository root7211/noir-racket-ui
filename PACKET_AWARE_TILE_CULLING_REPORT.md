# Noir Packet-Aware Tile Culling：编译期 Packet Bounds 与 Tile Membership

**作者：Manus AI**  
**实现范围：** `#lang noir/ui` 的宏展开期 IR、Scene JSON ABI、Racket 回归 oracle，以及与现有 Rust/wgpu Placement Renderer 的兼容性验证。  
**目标：** 将 glyph packet 的屏幕 bounds 和每个 damage/scissor tile 的最小 glyph placement 提交范围完全固定在编译期，使后端无需在运行时判断 packet 与 tile 的相交关系。

> 本阶段只实现和验证了 **Racket 编译器输出的 culling plan**。现有 Rust host 能无损读取包含新字段的 Scene 并完成真实 X11/wgpu 验证，但仍提交完整 packet；下一阶段才会让 host 的 tile draw loop 直接消费 `glyph_packet_ranges`。因此，本报告不把“后端已跳过 draw”误表述为已完成事实。

## 1. 编译器问题与新契约

此前 `Glyph Placement Plan` 已固定每个 glyph 的 NDC quad、UV、page、clip/z/batch，以及 `Glyph Draw Packet` 的连续 placement range。即便 render schedule 已使用 scissor tile，host 在一次 tile redraw 中仍会遍历并提交全部 glyph packets，再让 scissor 在 rasterization 阶段丢弃 tile 外像素。

新增的编译器契约是：每个 packet 具有精确的 clip-aware screen bounds；每个 render tile 直接具有零个或多个 `glyph-packet-range`。range 指定包索引、连续 placement 起点、数量、其与 tile 相交后的 bounds，以及 dynamic 属性。后端只需遍历这些小列表，而不扫描 UI tree、layout plan、glyph placement 全表或 packet bounds。

| 产物 | 编译期字段 | 后端将来可执行的最短操作 |
|---|---|---|
| `glyph_draw_packets[i]` | `bounds`、page、clip/z/batch、placement interval | 进行 packet-level资源绑定与固定 draw 基线 |
| `render_tile.glyph_packet_ranges[j]` | `packet_index`、`first_placement`、`placement_count`、`bounds`、dynamic | `draw(0..6, first_placement..first+count)` |
| `frame_schedule` | 三个离散 4-byte glyph-ID writes | action 后仅重绘包含对应 range 的 text tile |

## 2. IR 数据模型

运行时 `glyph-draw-packet` 增加 `bounds`，并新增 `glyph-packet-range`。对应的 compiler IR 是 `c-glyph-packet` 和 `c-glyph-packet-range`；`c-render-tile` 增加 `glyph-packet-ranges` 字段。

```racket
(struct glyph-draw-packet
  (id atlas-page first-placement placement-count
      first-glyph-byte-offset glyph-byte-length
      nodes bounds clip-stack-id clip-rect z-layer batch-key dynamic?)
  #:transparent)

(struct glyph-packet-range
  (packet-id packet-index first-placement placement-count bounds dynamic?)
  #:transparent)

(struct render-tile
  (x y width height nodes draw-ranges glyph-packet-ranges
     fallback-reason selected-strategy candidate-costs)
  #:transparent)
```

`packet-index` 是 `scene-glyph-draw-packets` 的稳定数组地址，避免后端以字符串查找 packet。`first-placement` 和 `placement-count` 都是已经证明属于该 packet 的连续 range；它们与 Rust Placement Buffer 的 instance address 直接相同。

## 3. 编译 packet bounds

每个 `c-glyph-placement` 持有 NDC 左下角和 NDC 尺寸。compiler 使用固定 640×360 target 将每个 glyph quad 恢复为 screen-space rect：

```racket
(define (glyph-placement-screen-rect placement)
  (define pos (c-glyph-placement-ndc-pos placement))
  (define size (c-glyph-placement-ndc-size placement))
  (list (* (+ (first pos) 1.0) 320.0)
        (* (- 1.0 (+ (second pos) (second size))) 180.0)
        (* (first size) 320.0)
        (* (second size) 180.0)))
```

`finish-packet` 对 packet 内 glyph rect 做 axis-aligned union，随后与 compiler 已计算的 `clip-rect` 求交：

```racket
(define bounds
  (or (rect-intersection
       (rect-union (map glyph-placement-screen-rect
                        (reverse reverse-placements)))
       (c-glyph-placement-clip-rect first))
      (raise-syntax-error 'text
                          "glyph packet is fully clipped at compile time"
                          (c-node-source root))))
```

这种定义不是使用整个 text node 的 layout rect。它排除了 padding、baseline 空白和 run 未覆盖区，且保证 bounds 已遵守 clip stack。对于 dashboard，产物如下。

| Packet | Atlas page | placement interval | 编译期 bounds `[x, y, width, height]` |
|---|---:|---:|---|
| `glyph-packet-page1-slot0-24` | 1 | `0..25` | `[102.64, 73.32, 537.36, 17.36]` |
| `glyph-packet-page0-slot25-30` | 0 | `25..31` | `[77.92, 129.32, 502.76, 17.36]` |

第一个 packet 是静态 title；第二个 packet 仍可压缩两个动态 run，因为它们具有相同 page、clip/z/batch 和 dynamic 属性，但 compiler 不会在 tile 中错误地提交其中未命中的 placements。

## 4. Tile culling 与 placement subrange 压缩

Tile culling 分两层完成。第一层对 packet bounds 与 tile rect 求交，实现常数时间的 packet early reject。第二层只针对命中的 packet，检查每个 glyph 的 effective rect（glyph quad 与 clip rect 的相交）是否与 tile 相交，然后把按 slot 连续的 glyph 合并成 `c-glyph-packet-range`。

```racket
(define (compile-glyph-tile-ranges tile placements packets)
  (define target (tile-rect tile))
  (append-map
   (lambda (packet packet-index)
     (if (not (rect-intersection (c-glyph-packet-bounds packet) target))
         '()
         (let* ([first (c-glyph-packet-first-placement packet)]
                [count (c-glyph-packet-placement-count packet)]
                [packet-placements (take (drop placements first) count)]
                [selected
                 (filter values
                         (for/list ([placement (in-list packet-placements)])
                           (define effective
                             (glyph-placement-effective-rect placement))
                           (and effective
                                (rect-intersection effective target)
                                (cons placement effective))))])
           (compress-glyph-tile-ranges
            packet packet-index selected tile))))
   packets (range (length packets))))
```

`compress-glyph-tile-ranges` 只会合并 slot 相邻的 selection。因此 page-0 packet 虽然全局范围是 slots `25..30`，FPS tile 得到 `25..28`，latency tile 得到 `28..31`；两者之间没有为了“节省 draw call”而提交任何 tile 外 glyph。

## 5. 动态 text 进入 Damage Plan

旧 Render Schedule 的 tile 候选仅来自 progress 和按钮动画。现在 `compile-render-schedules` 从 `c-action-plan-text-updates` 提取已有固定 Layout Plan rect，并将 FPS/latency 加入 tile 候选：

```racket
(define text-rects
  (append-map
   (lambda (plan)
     (for/list ([binding (in-list (c-action-plan-text-updates plan))])
       (define layout (hash-ref layout-by-id (c-binding-node-id binding)))
       (c-rect (c-binding-node-id binding)
               (c-layout-x layout) (c-layout-y layout)
               (c-layout-width layout) (c-layout-height layout))))
   plans))
```

这不会引入 runtime layout：这些 rect 已是宏展开期常量。它只让 `refresh-fps` 与 `refresh-latency` 有各自可供 culling 的 scissor tile。

## 6. Dashboard 的实际 tile membership

最终 schedule 共有五个 tile。两个 metrics tile 分别只提交 dynamic page-0 packet 的三个 glyph；title packet 在所有局部 damage tile 中都不出现。

| Tile | Rect | Strategy | glyph packet ranges | 本 tile 的 glyph instances |
|---:|---|---|---|---:|
| 0 | `[46, 124, 266, 28]` | `fragment` | packet 1, placement `25..28` | 3 |
| 1 | `[320, 124, 266, 28]` | `fragment` | packet 1, placement `28..31` | 3 |
| 2 | `[34, 180, 572, 22]` | `full-tile-redraw` | 无 | 0 |
| 3 | `[46, 230, 174.67, 46]` | `fragment` | 无 | 0 |
| 4 | `[411.33, 230, 174.67, 50]` | `fragment` | 无 | 0 |

因此，目标 host consume path 的单一 FPS 更新会是：

```text
refresh-fps action
  → queue.write_buffer: [800,804), [832,836), [864,868)
  → select tile 0
  → submit packet 1 / placement instances 25..28
  → 3 glyph quads
```

静态 title 的 25 glyph page-1 packet 在该局部重绘中不会被提交。

## 7. 宏展开期不变量

`assert-glyph-tile-culling!` 在 Scene 构造前检查每个 tile range。它验证：

| 不变量 | 失败条件 |
|---|---|
| packet index | 不是 `glyph_draw_packets` 的有效非负 index |
| packet identity | index 指向 packet 的 ID 与 range 的 `packet-id` 不一致 |
| placement ownership | range 不完全落在 packet 的 `[first, first+count)` 内，或为空 |
| bounds validity | range bounds 或 packet bounds 不与 tile 相交 |
| glyph exactness | range 内每个 glyph 的 effective rect 不与 tile 相交 |

这确保后端可以把 `glyph_packet_ranges` 当作执行计划，而不是再做防御性 tree/geometry 搜索。

## 8. Scene JSON ABI

`glyph_draw_packets` 新增：

```json
{
  "id": "glyph-packet-page0-slot25-30",
  "atlas_page": 0,
  "first_placement": 25,
  "placement_count": 6,
  "bounds": [77.92, 129.32, 502.76, 17.36],
  "dynamic": true
}
```

每个 `render_schedules[].tiles[]` 新增：

```json
"glyph_packet_ranges": [
  {
    "packet_id": "glyph-packet-page0-slot25-30",
    "packet_index": 1,
    "first_placement": 25,
    "placement_count": 3,
    "bounds": [77.92, 129.32, 228.76, 17.36],
    "dynamic": true
  }
]
```

该 schema 与已有 `draw_ranges` 并存：前者是 glyph Placement Buffer 的 instance ranges，后者是普通 44-byte QuadInstance ranges。

## 9. 验证结果与复现

| 层次 | 命令或 oracle | 结果 |
|---|---|---|
| Racket 回归 | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 通过；验证 2 packet bounds、5 tiles、两个 3-glyph range、其余 tile 的零文本 range |
| 宏展开期 | `assert-glyph-tile-culling!` | 通过；验证 packet index/ID、placement ownership、bounds 和逐 glyph tile 相交 |
| Scene 导出 | `racket tools/export-dashboard.rkt out/tile-culling.scene.json` | 通过；输出新 JSON 字段 |
| 真实宿主兼容 | `./tools/verify_winit_host.sh out/tile-culling.scene.json` | 通过；真实 Vulkan/llvmpipe、wgpu Surface、Xvfb、X11 输入、12-byte glyph ID updates |

可复现命令：

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" racket tests/run.rkt

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/tile-culling.scene.json

./tools/verify_winit_host.sh out/tile-culling.scene.json
```

## 10. 关键文件

| 文件 | 变更 |
|---|---|
| `noir/ui/main.rkt` | packet `bounds`、`glyph-packet-range`、tile culling、compile-time proof、Scene JSON lowering |
| `tests/run.rkt` | packet bounds、五个 tile、两个 3-glyph dynamic subrange 与零提交 tile oracle |
| `tools/inspect-tile-culling.rkt` | 只读检查工具，打印每 tile 的 strategy、quad ranges、glyph packet ranges 与 bounds |
| `out/tile-culling.scene.json` | 可由后端直接消费的 packet-aware schedule 示例 |

> 结论：Noir 编译器已把“哪些文本 glyph 需要在每个 damage tile 中提交”变为可审计的静态 Scene 数据。下一阶段只需让 Rust `draw_glyph_packets(tile)` 使用该字段，即可把当前的 scissor-only 文本路径变成真正的 packet-aware submission culling。
