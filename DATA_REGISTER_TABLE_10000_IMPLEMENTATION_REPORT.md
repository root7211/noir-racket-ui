# Compact `data-register-table` Integration Report

## Result

The compact `data-register-table` architecture is now a first-class Noir Scene artifact and an executable Rust renderer path. It supports a fixed logical capacity of **10,000 rows** while materializing only **four physical GPU row templates** and three visible rows. It deliberately does **not** serialize a 10,000-element label vector or approximately 19,994 directed adjacent viewport transitions.

> Runtime scroll selects a bounded viewport cursor, applies a fixed physical-ring template, copies fixed-width pre-shaped glyph IDs from the logical register arena to compiler-addressed physical glyph cells, and submits the three visible row ranges.

## Compiler Artifact

The new compact syntax is a restricted virtual-list form:

```racket
(virtual-list #:id telemetry-registers
              #:logical-capacity 10000
              #:physical-slots 4
              #:visible-rows 3
              #:row-height 28
              #:max-chars 10
  (data-register-table #:id telemetry-data #:seed "ROW VALUE")
  (row-template ((register-a "ROW VALUE")
                 (register-b "ROW VALUE")
                 (register-c "ROW VALUE")
                 (register-d "ROW VALUE"))))
```

The Scene exports one compact artifact instead of an expanded table:

| Field | Value in fixture | Meaning |
|---|---:|---|
| `logical_capacity` | 10,000 | Fixed maximum logical rows. |
| `physical_slots` | 4 | GPU row templates and row-tile arena size. |
| `visible_rows` | 3 | Viewport draw/glyph subranges. |
| `register-width` | 10 | Fixed glyph-ID width of every logical register. |
| `seed` | `ROW VALUE` | Compile-time seed copied to the initial arena. |
| `scroll_transitions` | 0 | Explicit transitions are intentionally absent. |

The exported 10,000-row Scene is **43,432 bytes**. Its size is dominated by the fixed UI/renderer artifact and remains independent of a per-viewport transition expansion.

## Rust Runtime and Proof

Rust deserializes `data_register_table` into a `CompiledDataRegisterTable`. At startup it validates all artifact boundaries: logical capacity, physical-slot relation, atlas page, uppercase-ASCII seed, register width, canonical ring slots, zero expanded transition objects, physical instance/glyph offset tables, contiguous row DrawRanges and glyph subranges. It then creates a fixed-width glyph-ID arena of `10,000 × 10 = 100,000` `u32` values.

The hot scroll path does not look up a node, layout, text string, glyph atlas entry, or transition object. For each of four physical slots it computes the compiler-fixed ring selector from the viewport cursor, applies pre-validated base Y coordinates, copies the entering logical register's glyph IDs to physical glyph cells, and submits only the current three physical row DrawRanges and glyph subranges.

A `--data-register-patch LIST LOGICAL_INDEX VALUE` test entry point validates runtime data binding. It accepts only the admitted fixed-width uppercase ASCII domain, updates one arena register, and writes GPU glyph cells only if that logical row is currently visible.

## Real X11/Vulkan Validation

The 10,000-row fixture was run with the Rust 1.75 Noir host, X11 via Xvfb, wgpu Vulkan/llvmpipe, and real X11 wheel input. The following checks passed.

| Check | Observed result |
|---|---|
| Scene compactness | `logical_capacity=10000`, `physical_slots=4`, `transition_count=0`. |
| Template scroll | Wheel reaches viewport 5 with row tiles `[1,2,3]`. |
| Vertex submission | `3` row ranges / `6` quad instances / `3` glyph subranges / `27` placements. |
| Packet scope | `worklist=no-packets`. |
| Visible update | Logical row 1 writes only its 9 physical glyph cells. |
| Non-visible update | Logical row 9999 changes the arena only; no immediate GPU range is written. |
| Existing compiler regression | Racket full suite passes. |
| Release build | Rust host release build passes. |

## Boundary

This implementation proves compact fixed-capacity data binding and bounded scrolling. The initial arena is seeded uniformly by design; it is not a claim that Noir has implemented an unrestricted external database, Unicode text shaping, asynchronous fetching, or arbitrary-height list layout. Those features would require separate resource and admission plans and must not reintroduce runtime tree traversal.

The next GUI-focused extension is a compiled `data-source update batch`: a fixed set of logical register updates lowered to non-overlapping physical patches when visible, plus a compiler-proved no-op GPU path when all updated rows are offscreen.
