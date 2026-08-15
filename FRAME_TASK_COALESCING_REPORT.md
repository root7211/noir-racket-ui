# Noir Frame-Task Coalescing：编译期 conflict winner 执行计划

**作者：Manus AI**  
**实现范围：** `#lang noir/ui` Racket 宏展开期 IR、Scene JSON、Racket regression oracle、现有 Rust/wgpu/X11 宿主兼容验证。  
**目标：** 将已有的 `frame_schedule`、priority、`conflict_graph` 与 Action-Aware Tile Selection 降低为后端可直接执行的 **Frame-Task Coalesced Batch Plan**：固定执行顺序、winner-only byte writes、被消除的 write segment、合并 tile IDs 与对应 conflict 边证据。

> 普通 scheduler 需要在运行时对 task 排序、检测 range overlap、确定 winner、去除被覆盖 write、合并 damage。Noir 将这些步骤移入宏展开期：后端只需按 compiler batch 中的数组顺序执行 winner writes，并使用 compiler 已合并的 tile IDs。

## 1. 新 IR 与 Scene JSON ABI

Runtime Scene 新增 `frame-coalesced-batches` 字段：

```racket
(struct frame-coalesced-write (task-id offset byte-length) #:transparent)
(struct frame-coalesced-elimination (task-id offset byte-length winner) #:transparent)
(struct frame-coalesced-batch
  (id task-ids execution-order winner-writes eliminated-writes
      merged-tile-ids conflict-edges)
  #:transparent)
```

每个 batch 的 JSON 具有如下结构：

```json
{
  "id": "coalesced-press-refresh-fps-button",
  "task_ids": ["hover-refresh-fps-button", "pressed-refresh-fps-button"],
  "execution_order": ["hover-refresh-fps-button", "pressed-refresh-fps-button"],
  "winner_writes": [
    {"task_id": "pressed-refresh-fps-button", "offset": 528, "byte_length": 8},
    {"task_id": "pressed-refresh-fps-button", "offset": 544, "byte_length": 16}
  ],
  "eliminated_writes": [
    {
      "task_id": "hover-refresh-fps-button",
      "offset": 544,
      "byte_length": 16,
      "winner": "pressed-refresh-fps-button"
    }
  ],
  "merged_tile_ids": [3],
  "conflict_edges": [
    {
      "left": "hover-refresh-fps-button",
      "right": "pressed-refresh-fps-button",
      "winner": "pressed-refresh-fps-button",
      "overlaps": [{"offset": 544, "byte_length": 16}]
    }
  ]
}
```

| 字段 | 后端含义 |
|---|---|
| `task_ids` | 形成该同帧批次的 compiler 已知 task 集合 |
| `execution_order` | 稳定低 priority → 高 priority 顺序；同 priority 使用 task ID 字典序 |
| `winner_writes` | 唯一需要执行的 byte segments；不会包含被后续 winner 覆盖的字段 |
| `eliminated_writes` | 被省略的具体 byte segments 及其 compiler winner，作为审计证据 |
| `merged_tile_ids` | member task 的升序、无重复 tile union |
| `conflict_edges` | batch 内真实发生的既有 conflict graph edge |

## 2. 稳定 winner 语义

本阶段复用而不复制既有 `task-winner` 规则：较高 priority 胜出；priority 相同时，用 task ID 字典序确定 winner。这保证 conflict graph、batch winner-only writes 与未来 Rust executor 使用同一规则。

```racket
(define (task-execution-before? left right)
  (or (< (c-frame-task-priority left) (c-frame-task-priority right))
      (and (= (c-frame-task-priority left)
              (c-frame-task-priority right))
           (string<? (symbol->string (c-frame-task-id left))
                     (symbol->string (c-frame-task-id right))))))
```

`execution-order` 保留全部 member task，用于审计与未来按 batch 触发的高层副作用；但 field/GPU write executor 只执行 `winner-writes`。

## 3. 字节级 winner-only segmentation

每个 task write 是 `[offset, byte_length)`。编译器收集所有起止边界，将地址空间切分为非重叠的最小区间。对每个被一个或多个 task 覆盖的区间，使用 `task-winner` 选择唯一 owner；其余 contender 产生一个 `eliminated` record。

```racket
(define (winner-only-write-plan tasks)
  (define boundaries
    (sort (remove-duplicates
           (append-map
            (lambda (task)
              (append-map
               (lambda (write)
                 (list (first write) (+ (first write) (second write))))
               (c-frame-task-writes task)))
            tasks))
          <))

  (for ([start (in-list boundaries)] [end (in-list (rest boundaries))])
    (define contenders
      (filter (lambda (task)
                (ormap (lambda (write)
                         (and (<= (first write) start)
                              (<= end (+ (first write) (second write)))))
                       (c-frame-task-writes task)))
              tasks))
    ;; choose task-winner; emit winner segment and loser elimination segments
    ...)
  ...)
```

因此即使未来出现 4-byte/8-byte/16-byte 部分重叠，compiler 仍能证明正确的 winner，而无需把任一范围粗暴扩展到整个 field。相邻且属于相同 task 的 winner segment 会合并；最终再按 `execution-order` rank、再按 offset 排序，保证后端数组顺序稳定。

## 4. 编译的 batch 集合

当前 dashboard 的每个按钮生成两个受限、可审计 batch：

| Batch | Member task | merged tiles | winner-only 结果 |
|---|---|---:|---|
| `coalesced-press-refresh-fps-button` | hover FPS, pressed FPS | `[3]` | pressed 保留 pos `[528,536)` 与 color `[544,560)`；hover color 16 bytes 被删除 |
| `coalesced-activate-refresh-fps-button` | release FPS, refresh FPS | `[0,3]` | release pos/color + 三个 4-byte FPS glyph IDs |
| `coalesced-press-refresh-latency-button` | hover, pressed latency | `[4]` | pressed 保留；hover color 被删除 |
| `coalesced-activate-refresh-latency-button` | release, refresh latency | `[1,4]` | release pos/color + 三个 latency glyph IDs |
| `coalesced-press-advance-progress-button` | hover, pressed progress button | `[5]` | pressed 保留；hover color 被删除 |
| `coalesced-activate-advance-progress-button` | release, advance progress | `[2,5]` | release pos/color + progress size.x 4 bytes |

FPS press batch 的精确输出为：

```text
execution order:
  hover-refresh-fps-button → pressed-refresh-fps-button

winner writes:
  pressed-refresh-fps-button [528,536)
  pressed-refresh-fps-button [544,560)

eliminated:
  hover-refresh-fps-button [544,560)
  winner: pressed-refresh-fps-button

tile union: [3]
```

FPS activate batch 无字段冲突：release 写 button bytes `[528,536)`、`[544,560)`，action 写 glyph IDs `[800,804)`、`[832,836)`、`[864,868)`；但 compiler 仍预先给出 tile union `[0,3]`，使 host 无需在 release/action 分支做 mask union。

## 5. 宏展开期证明

`assert-frame-coalesced-batches!` 证明下列不变量。

| 不变量 | 证明条件 |
|---|---|
| 执行顺序 | `execution-order == sort(tasks, task-execution-before?)` |
| tile union | `merged-tile-ids == sort(remove-duplicates(member tile IDs))` 且非空 |
| winner ownership | 每一个 winner segment 都完全属于其 source task 的原始 write range |
| elimination winner | 每一个 eliminated segment 的 `winner` 必须满足既有 `task-winner` |
| conflict isolation | batch 中每条 edge 的 left/right task 必须均属于 batch |

任何不满足条件的 DSL 在 macro expansion 时 `raise-syntax-error`；不可能作为运行时 Scene 交给后端。

## 6. 回归与真实验证

| 层级 | 验证 | 结果 |
|---|---|---|
| Racket compiler oracle | `tests/run.rkt` 检查全部 6 batch、FPS press/activate 的 task order、winner writes、elimination、tile union 与 edge | 通过 |
| Scene lowering | 导出 `out/frame-coalescing.scene.json`，包含 `frame_coalesced_batches` | 通过 |
| Placement/Tile host compatibility | Rust serde 忽略尚未消费的 batch metadata；既有 Action-Aware path 使用相同 Scene 成功执行 | 通过 |
| 真实 GPU/input | Vulkan/llvmpipe、wgpu Surface、Xvfb、`xdotool` 的三个按钮点击 | 通过 |
| 最短既有 path | FPS/latency 仍各 12-byte glyph patch，progress 仍为 4-byte patch；tile/glyph submission 未回退 | 通过 |

复现命令：

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" racket tests/run.rkt

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/frame-coalescing.scene.json

PLTCOLLECTS="$PWD:" racket tools/inspect-frame-coalescing.rkt
./tools/verify_winit_host.sh out/frame-coalescing.scene.json
```

## 7. 当前边界与下一阶段

本阶段的 compiler 已完整生成 batch execution plan；当前 Rust host 尚未执行 `frame_coalesced_batches`，它仍在 hover/pressed/release/action 到达时分别 patch。Scene metadata 已验证能与真实 host 共存，但“删除 hover write 并一次执行 pressed batch”的 runtime 采纳是下一步。

下一阶段应实现 **Rust Coalesced Batch Executor**：在 pointer event 中选择 compiler batch ID，按 `winner-writes` 执行唯一 field patch/动态 GPU patch、直接使用 `merged_tile_ids` mask，并保留 timestamp query 量化前后 `queue.write_buffer` 与 tile submission 差异。

> 结论：Noir 现在已将 task conflict 的判定从运行时 scheduler 移至 compiler，并输出字节级 winner proof。后端不必理解 priority、overlap 或 damage；它只执行被证明不可省略的 writes 和 tile IDs。
