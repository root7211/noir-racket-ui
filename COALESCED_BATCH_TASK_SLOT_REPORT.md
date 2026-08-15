# Coalesced Batch Action Task Slot Lowering

## 结果

Coalesced Batch 现在拥有第二份、可执行的编译期任务地址表：`execution_refs`。原有 `task_ids`、`execution_order` 与 winner-write `task_id` 被保留为 compiler proof 与人类审计镜像；运行时 batch dispatcher 不再通过 `scene.actions.contains_key(task_id)` 判断一个 task 是否为业务 action。

> 运行时分派现在是 `CompiledTaskRef::Transient(index)` 或 `CompiledTaskRef::Action(index)`。索引由 Racket 宏展开确定，并在 Rust 建窗前证明其与 task kind、audit ID、Action Slot、赢家写入及 tile plan 一致。

## Racket 编译期 ABI

runtime Scene IR 新增：

```racket
(struct batch-task-ref (kind index id) #:transparent)
(struct frame-coalesced-batch
  (id task-ids execution-order execution-refs
      winner-writes eliminated-writes merged-tile-ids conflict-edges
      strategy-id candidate-costs selection-proof)
  #:transparent)
```

`frame-coalesced-batches->datum` 以同一个 `action-indexes` map 降低 batch execution order：业务 action 生成

```racket
(batch-task-ref 'action action-index 'action-id)
```

而 release/hover/pressed 等瞬态任务按照 task ID 字典序得到 transient index：

```racket
(batch-task-ref 'transient transient-index 'transient-task-id)
```

因此 action table 与 batch table 共用相同 canonical Action Slot ABI；不需要在 Rust 重新从 action string 推断类别。Scene JSON 中新增 `execution_refs`，例如 refresh-fps activate batch：

```json
"execution_refs": [
  {"kind":"transient", "index":7, "id":"release-refresh-fps-button"},
  {"kind":"action", "index":1, "id":"refresh-fps"}
]
```

## Rust startup proof

Rust serde 增加 `BatchTaskRef`，并将每个 batch 压缩为：

```rust
#[derive(Clone, Debug)]
enum CompiledTaskRef {
    Action(usize),
    Transient(usize),
}

struct CompiledBatch {
    id: String,
    execution_refs: Vec<CompiledTaskRef>,
    winner_writes: Vec<FrameCoalescedWrite>,
    tile_mask: u64,
    strategy: CompilerStrategy,
}
```

`compiler_coalesced_batches()` 保留既有 priority order、winner-write ownership、eliminated-write winner、conflict-edge 和 replay strategy proofs，并新增以下 admission：

| Ref kind | 启动期必须证明 | 事件期使用 |
|---|---|---|
| `action` | task kind 为 `action`；ref ID 与 Action Slot ID 相同；ref index 等于 canonical action index | `action_slot_ids[index]` 与已编译 action plan |
| `transient` | task kind 不为 `action`；ref ID 与 sorted transient task table 的 index 相同 | `transient_task_ids[index]` |

`apply_compiler_batch_writes()` 遍历 `CompiledTaskRef`，而不执行 `scene.actions.contains_key(task_id)`。winner writes 仍以 compiler audit task ID 标记，以便保持已有的 byte-range proof 可审计。

## 真实鼠标验证

`tools/verify_winit_host.sh` 已扩展为真实 Xvfb/X11 点击 oracle。它用 compiler Event Map 固定命中坐标依次点击 FPS、latency 与 progress 三个按钮，并确认三条 activate batch 的实际日志：

| Batch | Tagged refs |
|---|---|
| `coalesced-activate-refresh-fps-button` | `Transient(7), Action(1)` |
| `coalesced-activate-refresh-latency-button` | `Transient(8), Action(2)` |
| `coalesced-activate-advance-progress-button` | `Transient(6), Action(0)` |

同时验证 release transient GPU ranges、action state slot 写入、glyph/instance patch、compiler-selected strategy 和 merged tile submission。验证命令为：

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd ..
PLTCOLLECTS="$PWD:" NOIR_ENTRY_MODULE="examples/dashboard.rkt" \
  racket tools/export-dashboard.rkt out/registry-match.scene.json
tools/verify_winit_host.sh
```

所有步骤已通过。

## 余下的审计字符串

`FrameCoalescedWrite.task_id` 与 `execution_order` 仍保存 task symbol，原因是它们是 conflict/winner proof 的可读证据，并用于启动期交叉验证。它们不再决定 action/transient runtime dispatch。若需要彻底移除这些 audit strings，可在后续把 winner-write owner 也改为 `BatchTaskRef`；这将是格式紧缩而非语义能力缺口。
