# `data-update-batch` Visibility-Split Execution Report

## Implemented Runtime Contract

The compact register renderer now accepts a fixed batch of `(logical-index, uppercase-ASCII value)` updates. Each record has a fixed register width and is written first into the preallocated logical glyph-ID arena. The runtime uses the current compiler-proved viewport/ring mapping to classify updates.

| Update class | CPU-side work | GPU writes | Render request |
|---|---|---|---|
| Visible logical row | Fixed-width arena overwrite and fixed physical glyph-cell writes | One glyph ID write per glyph cell | One fused viewport `RenderRequest` for the whole batch |
| Offscreen logical row | Fixed-width arena overwrite | None | None |
| Mixed batch | Both paths | Only visible physical slots | Exactly one fused request if any record is visible |

The executor rejects duplicate logical indices, out-of-range indices, over-width values, and strings outside the admitted uppercase-ASCII domain. These checks enforce the register ABI; they do not search nodes, derive layout, shape arbitrary text, or construct GPU ranges.

## Validation

The compact 10,000-row Scene was executed with X11 through Xvfb and the wgpu Vulkan/llvmpipe backend.

| Case | Input batch | Result |
|---|---|---|
| Visible fused batch | `0=LIVE ZERO,1=LIVE ONE,2=LIVE TWO` | 3 logical updates, 27 glyph-cell writes, one local RenderRequest, one viewport-only submit. |
| Fully offscreen batch | `9000=TAIL ONE,9001=TAIL TWO,9002=TAIL THREE` | 3 logical updates, 0 glyph-cell writes, 0 RenderRequests, 0 viewport submit. |

The release log records the first case as `updates=3 visible=3 arena-only=0 gpu-glyph-writes=27 render-request=true` and the second as `updates=3 visible=0 arena-only=3 gpu-glyph-writes=0 render-request=false`.

## DSL Integration Boundary

The compiler already provides the fixed `data-register-table` artifact and register-width/capacity proof that this executor consumes. The newly added `--data-update-batch` host entry point is a reproducible execution harness for the fixed batch ABI. A declarative Racket `data-update-batch` event form remains the next syntactic lowering step: it should emit the same ordered logical-index batch plan into Scene JSON, rather than change this runtime executor or introduce a dynamic callback list.
