# Frame Task / Coalesced Batch Worklist Slot Lowering

**作者：Manus AI**  
**实现状态：核心 ABI、Racket lowering、Rust admission 与当前 Settings X11 路径已完成**

## 编译期任务 ABI

`frame-task` 与 compile-time `c-frame-task` 已增加 `packet_worklist_index`。该字段进入 Scene JSON 的 `frame_schedule`，并由 macro expansion 固定：`release`、`hover`、`pressed` 与普通 instance-only `action` 指向 `no-packets` worklist；transaction task 指向由 `transaction-<id>` worklist 派生的固定 index。

Racket 在生成 `packet_worklists` 后运行 `annotate-frame-task-worklists`。该 pass 对 transaction task 的 ID 与 `transaction-plans` 做静态对应，写入 transaction-local worklist index；任何缺失的 `no-packets` 或 transaction worklist 都在宏展开期拒绝。随后才重建 conflict graph、coalesced batches 与 strategy proof，因此 batch winner proof 与 worklist slot 属于同一不可变 compiler artifact。

| Task kind | Compiler worklist |
|---|---|
| `hover` / `pressed` / `release` | `no-packets` |
| 普通 Action Slot | `no-packets`，除非后续 glyph-producing action pass 特别标注 |
| Transaction Slot | `transaction-<id>` |
| keyboard / Escape / single commit | 已有 field-local slot array |
| full replay | `all-packets` |

## Rust 宿主 ABI

Rust `FrameTask` 读取 `packet_worklist_index`。`compiler_coalesced_batches` 对每一个 compiler execution ref 验证该 index 在 Scene packet worklist table 内，并在 `CompiledBatch.task_worklist_indices` 以与 `execution_refs` 相同顺序保存不可变数组。

`apply_compiler_batch_writes` 逐 pair 输出审计记录：

```text
coalesced-batch task-worklist-slot: task=Transaction(0) index=6
```

并只从该 array 选择 batch 的 packet activity worklist。它不会根据 task ID、glyph node、state 名称或 runtime damage 重建 packet依赖。为了保持现有 renderer API 的最小兼容面，选定 slot 暂通过 `pending_packet_worklist` 单次交给 `redraw_selected_tiles` 并立即由 renderer consume/reset；后续可将该函数签名改为显式 `worklist_index`，完全删除此兼容字段。

## 已验证结果

| 验证 | 结果 |
|---|---|
| Racket Command Palette 导出 | 通过，包含 `frame_schedule[*].packet_worklist_index` |
| Rust 1.75 / wgpu 0.20 release build | 通过 |
| 当前 Settings Form X11/wgpu | 通过；三 field local lists、Apply All transaction list、Escape与无 packet visual skip均保持正确 |
| 旧 registry-match 鼠标 harness | 需要重新导出；其保存的 Scene 使用旧 subgroup coverage ABI，启动期被正确拒绝为 `subgroup packets do not completely cover compiler glyph draw packet` |

这个拒绝是 ABI admission 的预期保护：不能将旧 compiler Scene 静默送入新 packet/worklist executor。重新用当前 Racket compiler 导出 registry showcase 后，鼠标 coalesced batch harness即可使用新的 `task_worklist_indices` 审计字段。

## 后续收尾

下一次小改动应将 `redraw_selected_tiles(worklist_index)` 参数显式化，删除 `Host.pending_packet_worklist`。那将把兼容传递状态也彻底移除，使 renderer 输入成为完全函数式的 `{ tile_mask, packet_worklist_index, strategy }`。 
