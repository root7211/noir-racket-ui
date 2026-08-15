# Renderer Worklist Parameterization Implementation

## Target Rust API

```rust
fn redraw_selected_tiles(
    &mut self,
    selected_mask: u64,
    strategy: Option<CompilerStrategy>,
    packet_worklist_index: usize,
    measure_gpu: bool,
    cpu_started: Option<Instant>,
) -> (SubmittedTileStats, Option<f64>, Option<u128>) {
    if selected_mask == 0 {
        return (SubmittedTileStats::default(), None, cpu_started.map(|t| t.elapsed().as_nanos()));
    }
    let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("noir-selected-tile-canvas"),
    });
    self.encode_packet_activity(&mut encoder, packet_worklist_index);
    // Existing scissor, indirect packet draw, timestamp, and submit logic follows unchanged.
}
```

## Compiler-produced task contract

Racket now serializes the following field on every frame task:

```json
{
  "id": "transaction-0",
  "kind": "transaction",
  "packet_worklist_index": 6
}
```

The macro pass `annotate-frame-task-worklists` assigns the index after field/transaction-local packet lists exist, then recomputes conflict and coalesced-batch plans. Pure visual tasks are fixed at index `2` (`no-packets`); a transaction task is fixed at its `transaction-<id>` packet union.

## Rust admission and batch propagation

```rust
#[derive(Debug, Deserialize)]
struct FrameTask {
    id: String,
    kind: String,
    priority: i32,
    writes: Vec<ByteRange>,
    tile_ids: Vec<usize>,
    packet_worklist_index: usize,
}

#[derive(Clone)]
struct CompiledBatch {
    id: String,
    execution_refs: Vec<CompiledTaskRef>,
    task_worklist_indices: Vec<usize>,
    winner_writes: Vec<FrameCoalescedWrite>,
    tile_mask: u64,
    strategy: CompilerStrategy,
}
```

`compiler_coalesced_batches` validates every task index against `Scene.packet_worklists` and stores it in the same order as `execution_refs`. The selected slot is therefore compiler data, never inferred from an action name, state, glyph range, or runtime damage region.

## Remaining mechanical migration

The release host currently consumes this explicit batch slot through a compatibility hand-off into `pending_packet_worklist`, which is reset on redraw. The final mechanical step is to update every invocation of `redraw_selected_tiles` to pass one of:

| Caller | Explicit slot |
|---|---:|
| full replay | `0` (`all-packets`) |
| hover / pressed / release / caret | `2` (`no-packets`) |
| keyboard field transition / Escape | `keyboard_packet_worklist_indices[focus_slot]` |
| single field commit | `keyboard_packet_worklist_indices[focus_slot]` |
| commit group / Apply All / Reset All | `transaction_packet_worklist_indices[transaction_index]` |
| compiled batch | last non-empty index in `batch.task_worklist_indices`, otherwise `2` |

After this signature migration, delete `Host.pending_packet_worklist` and all assignments to it. The WGSL interfaces do not change: `encode_packet_activity` already takes an explicit worklist index and populates the fixed 160-byte uniform worklist payload.

## Validation plan

Re-export every showcase after the Scene ABI extension. The legacy `registry-match.scene.json` is intentionally rejected by subgroup coverage admission because it predates the new compiler ABI; regenerate it before mouse coalesced-batch tests. Run Settings Form for keyboard/transaction cases, Command Palette for ASCII field cases, and regenerated registry mouse tests for transient/Action Slot cases.
