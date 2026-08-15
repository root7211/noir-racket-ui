# Scene `data_update_batches` Interpreter Report

## Implemented Pipeline

The Rust host now directly consumes the `data_update_batches` emitted by the Racket `virtual-list` compiler artifact. The path is entirely data driven:

> Racket DSL declaration → `virtual_list_plans[].data_update_batches` JSON → Rust serde ABI → startup proof → existing compact logical arena executor → fused `RenderRequest` → renderer.

The host adds `DeclaredDataUpdateBatch { id, table, updates }` to the Scene ABI and preserves the verified batches in `CompiledVirtualListPlan`.

## Startup Proof

For every compact `data_register_table`, the startup validator rejects a batch unless all of the following hold:

| Invariant | Validation |
|---|---|
| Batch identity | Batch IDs are unique inside the list. |
| Target table | `batch.table` exactly equals the admitted compact register table ID. |
| Content | The batch is non-empty. |
| Logical address | Every update index is below logical capacity. |
| Conflict | Every logical index is unique inside the batch. |
| Text ABI | Each value fits the fixed register width and is uppercase ASCII or space only. |

No event-time UI tree traversal, text shaping, layout calculation, or GPU range discovery is introduced.

## Automatic Execution

After all Scene artifacts and GPU resources have been admitted, `Host::new` calls `execute_scene_data_update_batches`. It iterates the compiler-fixed list/batch order and invokes the existing `apply_compact_data_update_batch` executor. A visible group becomes one fused local render request; an all-offscreen group remains an arena-only update.

The fixture declares:

```racket
(data-update-batch #:id bootstrap-telemetry
  ((0 "LIVE ZERO") (1 "LIVE ONE") (2 "LIVE TWO")))
```

The exported Scene contains the exact fixed table binding and three ordered records.

## Real X11/Vulkan Evidence

The release host was started directly with the Racket-exported Scene and **without** `--data-update-batch` or `--data-register-patch` runtime input. It logged:

```text
scene-data-update-batch: id=bootstrap-telemetry list=telemetry-registers table=telemetry-data updates=3 source=compiler-artifact
data-update-batch: list=telemetry-registers updates=3 visible=3 arena-only=0 gpu-glyph-writes=27 render-request=true
```

The first window presentation follows the host's established full-canvas initialization path, which dispatches `all-packets`; the compiler batch has nevertheless already applied its fixed arena and glyph updates and enqueued its local request. Subsequent event-time batches retain the viewport-only `no-packets` path.

## Boundary

This delivery makes Scene-declared batches automatically executable at initialization. Binding those same static batch IDs to a specific input event is a separate Event Map extension; it should map an event directly to the already-admitted batch ID, not store arbitrary runtime callbacks.
