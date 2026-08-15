# Noir Action-Aware Tile Selection：编译期 `tile_ids` 计划

**作者：Manus AI**  
**实现范围：** Racket `#lang noir/ui` 宏展开期 task selection、runtime Scene IR、Scene JSON、Racket 回归 oracle 与现有 Rust/wgpu 宿主的兼容验证。  
**目标：** 让 action、hover、pressed 与 release 动画任务直接携带 compiler 固定的 render tile ID 列表，运行时不再做 damage union、rect-to-tile 相交、排序或去重。

> 这一步使“哪个 tile 需要被重绘”成为编译产物。当前 Rust host 尚未读取 `tile_ids` 来缩小其 dirty canvas tile loop；它仍能兼容新 Scene 并执行 packet-aware glyph culling。下一阶段只需消费本报告定义的 ID 列表，即可把 FPS action 收缩为 tile 0 的单次 3-instance glyph draw。

## 1. 新的运行时契约

此前 compiler 已输出固定 Render Tiles 和每 tile 的 `glyph_packet_ranges`，但 action dispatch 只设置 `canvas_dirty=true`。host 因而每次 dirty 都遍历完整 schedule，即使只有一个 action 的 12-byte glyph ID patch。

现在 compiler 同时为两个运行时对象输出 `tile_ids`：`action-plan` 给正常业务 action 使用；`frame-task` 给 hover、pressed、release 和 action scheduler 使用。它们都引用 `render_schedules[0].tiles` 的稳定数组下标。

| IR | 新字段 | 使用者 | 意义 |
|---|---|---|---|
| `action-plan` | `tile-ids` | `dispatch_action` | 业务 state/GPU patch 后的固定 dirty tile 列表 |
| `frame-task` | `tile-ids` | hover/pressed/release/frame scheduler | 瞬态视觉任务的固定 dirty tile 列表 |
| `render-schedule` | `task-ids` | 审计/后端 | 与 task selection table 对齐的完整任务集合 |

运行时不需要将 byte writes 反向映射至 UI node，也不需要从 damage rect 动态查找 scissor tile。它只需读取一个小型、升序、无重复整数列表。

## 2. IR 与 Scene JSON ABI

Runtime IR 被扩展如下。

```racket
(struct frame-task (id kind priority writes tile-ids) #:transparent)
(struct action-plan (id writes gpu-updates instance-updates damage tile-ids) #:transparent)
```

编译期 IR 同样增加该字段。

```racket
(struct c-frame-task (id kind priority writes tile-ids) #:transparent)
(struct c-action-plan
  (id action text-updates instance-updates damage tile-ids)
  #:transparent)
```

JSON 采用 `tile_ids` 名称。例如：

```json
"refresh-fps": {
  "gpu_updates": [{
    "node": "fps",
    "glyph_id_offsets": [800, 832, 864]
  }],
  "tile_ids": [0]
}
```

```json
{
  "id": "release-advance-progress-button",
  "kind": "release",
  "writes": [
    {"offset": 616, "byte_length": 8},
    {"offset": 632, "byte_length": 16}
  ],
  "tile_ids": [5]
}
```

## 3. 全部瞬态任务进入 Render Tile Plan

旧 schedule 只放入第一个与第三个按钮的 event rect，因而不能让所有 hover/pressed/release 任务拥有独立稳定 tile。现在 `compile-render-schedules` 把 Event Map 的全部按钮转换为 damage rect：

```racket
(define event-rects
  (for/list ([event (in-list events)])
    ;; pressed/release 的 2px 位移加 2px raster guard。
    (c-rect (c-event-node-id event)
            (c-event-x event) (c-event-y event)
            (c-event-width event)
            (+ (c-event-height event) 4.0))))
```

两个动态 text rect、progress rect 和三个 event rect 共同得到六个 tile。所有 frame tasks 被记录在 `render-schedule.task-ids`，确保 tile selection plan 不存在“可执行但未被 schedule 审计”的 task。

## 4. Task-to-Tile 编译算法

`compile-action-aware-tile-selection` 在 Render Tiles 固化后运行。它接收 root、layout、Event Map、原始 action plans、原始 frame tasks 和 render schedules，输出 tile IDs 已回填的 action plans/tasks。

对于 normal action，damage 来自两个静态来源：`c-action-plan-damage` 的 geometry layout 和 `c-action-plan-text-updates` 的固定 text layout。对于 hover、pressed、release，damage 使用 Event Map button rect 与 pressed/release 的固定 2px 位移/2px guard。所有这些值均来自宏展开期 IR。

```racket
(define (select-tile-ids damage-rects)
  (for/list ([tile (in-list tiles)] [tile-id (in-naturals)]
             #:when
             (ormap (lambda (damage)
                       (rect-intersection (tile-rect tile) damage))
                     damage-rects))
    tile-id))
```

`for/list` 的 tile 遍历顺序就是 final Render Tile 的数组顺序，因此输出天然严格递增；随后使用 `remove-duplicates` 和升序比较生成额外证明。此 pass 是 compiler 最后一次允许计算 damage→tile 相交的地方。

## 5. 静态不变量

编译器在构造 Scene 前验证每个 selected task。

| 不变量 | 失败时的宏展开期错误 |
|---|---|
| 非空 | task damage 未命中任何 compiled tile |
| 稳定顺序 | `tile_ids` 不是升序或包含重复 ID |
| 语义覆盖 | 每个 task damage rect 至少与一个 selected tile 相交 |
| 瞬态关联 | hover/pressed/release task 必须找到对应 Event Map binding |
| action 关联 | action task 必须在 action-plan table 中存在 |

核心检查为：

```racket
(unless (and (pair? ids)
             (equal? ids (sort (remove-duplicates ids) <)))
  (raise-syntax-error 'noir
                      "task tile IDs must be non-empty, unique and ascending"
                      (c-node-source root)))

(for ([damage (in-list (task-damage-rects task))])
  (unless (ormap
           (lambda (tile-id)
             (rect-intersection (tile-rect (list-ref tiles tile-id))
                                damage))
           ids)
    (raise-syntax-error 'noir
                        "selected tile IDs do not cover task damage"
                        (c-node-source root))))
```

## 6. Dashboard 编译结果

最终 dashboard schedule 固化为六个 tile。

| Tile ID | Rect `[x, y, w, h]` | 主要用途 | glyph packet submission |
|---:|---|---|---|
| 0 | `[46, 124, 266, 28]` | FPS action | packet 1，placements `25..28`，3 glyph |
| 1 | `[320, 124, 266, 28]` | latency action | packet 1，placements `28..31`，3 glyph |
| 2 | `[34, 180, 572, 22]` | progress action | 无 glyph |
| 3 | `[46, 230, 174.67, 50]` | FPS button hover/pressed/release | 无 glyph |
| 4 | `[228.67, 230, 174.67, 50]` | latency button hover/pressed/release | 无 glyph |
| 5 | `[411.33, 230, 174.67, 50]` | progress button hover/pressed/release | 无 glyph |

Action plans 的精确映射如下。

| Action | GPU/instance 写入 | `tile_ids` |
|---|---|---|
| `refresh-fps` | `[800,804)`、`[832,836)`、`[864,868)` | `[0]` |
| `refresh-latency` | `[896,900)`、`[928,932)`、`[960,964)` | `[1]` |
| `advance-progress` | `[316,320)` | `[2]` |

全部 transient task 同样是单 tile：FPS button 的 release/hover/pressed → `[3]`；latency button → `[4]`；progress button → `[5]`。

## 7. 真实验证与当前边界

| 验证层 | 命令或 oracle | 结果 |
|---|---|---|
| Compiler oracle | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 通过；验证 12 个任务及 3 个 action 的精确 tile IDs、六 tile schedule、packet subranges 与 conflict graph |
| Scene 导出 | `racket tools/export-dashboard.rkt out/action-tile-selection.scene.json` | 通过；输出 action/frame task 的 `tile_ids` |
| Rust/wgpu 兼容 | `./tools/verify_winit_host.sh out/action-tile-selection.scene.json` | 通过；真实 Vulkan/llvmpipe、Surface present、Xvfb 与 X11 input |
| 既有文本最短写入 | X11 oracle | FPS/latency 各 12 bytes，progress 4 bytes；tile glyph culling 仍只提交两个 3-instance dynamic ranges |

当前 Rust host 会接受这些附加字段，但仍因尚未实现 task selection 而在 canvas dirty 时遍历六个 tiles。它已经在每个 tile 内执行 glyph packet range culling，故不会提交静态 title packet；但是它尚未按照 action 的 `[0]` 或 `[1]` 跳过另一个 metrics tile。

## 8. 可复现步骤

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" racket tests/run.rkt

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/action-tile-selection.scene.json

./tools/verify_winit_host.sh out/action-tile-selection.scene.json

# 可选：查看 compiler 的 task-to-tile table
PLTCOLLECTS="$PWD:" racket tools/inspect-action-tile-selection.rkt
```

## 9. 关键文件

| 文件 | 作用 |
|---|---|
| `noir/ui/main.rkt` | task selection IR、动态/瞬态 damage lowering、tile ID proof、JSON/datum 输出 |
| `tests/run.rkt` | 12 task + 3 action 的 tile ID oracle；六 tile 与 glyph subrange 断言 |
| `tools/inspect-action-tile-selection.rkt` | 只读显示 action、frame task、tile 与 glyph range 编译结果 |
| `out/action-tile-selection.scene.json` | 后端下阶段直接消费的完整 Scene |

> 结论：Noir 已把“状态更新后哪些 tiles 必须被重绘”从运行时 damage 计算转为 compiler 的稳定整数跳转表。下一阶段在 Rust `dispatch_action`、hover/pressed/release 路径消费这些 IDs 后，FPS 更新将从 six-tile schedule loop 收缩为 **tile 0 → packet 1 → placements 25..28 → 一次 3-instance draw**。
