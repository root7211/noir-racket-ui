# Acknowledged Row State Plan v1 — Fixed Executor Report

**Author:** Manus AI  
**Status:** Implemented and verified  
**Scope:** Application-layer `#:row-state acknowledged`, Rust ABI admission, fixed logical-row state table, idempotent acknowledgement, compact-list recycle recovery, and real X11/Vulkan validation.

## 1. Result

`acknowledged_row_state_plan v1` completes Noir's first fixed-capacity, recoverable domain-state path. An application author declares only the Alerts business state:

```racket
(alerts #:seed "WARN  TIME  EDGE  RETRY" #:row-state acknowledged)
```

The compiler derives the state owner, capacity, fixed `u64` word geometry, acknowledgement action, physical row-color lanes, detail glyph range, and tile scope. The Rust host admits only that plan and creates one non-resizable `Box<[u64]>` table after startup proof.

| Application profile | Alerts logical capacity | Fixed words | Physical row lanes | Detail glyph cells |
|---|---:|---:|---:|---:|
| `standard` | 2,048 | 32 × `u64` | 3 | 29 |
| `compact` | 512 | 8 × `u64` | 3 | 29 |

## 2. Fixed execution path

The acknowledgement executor first validates that Alerts is the active owner view and that a logical row is selected. It then computes exactly one `word_index = logical / 64` and one bit mask. If the bit is already set, the action is consumed with zero state and GPU writes. Otherwise it commits the bit, the pre-proved cross-view count state, one physical row color lane, 29 Alerts detail glyph cells, eight Overview count glyph cells, and the compiled transaction tile mask.

> The state table is not a dynamic record store. It is one startup-proved, fixed-size word slice; execution uses only a bounded integer index and bit operation.

The outcome is an idempotent `open → acknowledged` transition. Repeating the operation cannot increment the Overview count or emit GPU writes.

## 3. Recovery path

Compact virtual-list scrolling continues to own geometry and glyph recycling. Its existing `sync_log_browser_row_colors` pass now queries the acknowledged bit for each rebound visible Alerts logical row. A set bit restores the compiler-proved acknowledgement color through the matching physical lane. Selecting that row also rebuilds `DETAIL <LEVEL> ACKNOWLEDGED` into the fixed 29-cell detail endpoint.

No additional component lookup, row object allocation, dynamic palette table, or full-frame layout pass is introduced. Systems has no acknowledged-row plan and remains on its prior log-level color path.

## 4. Admission and rejection

The host enforces an object-or-false Scene field and a required marker. Before normal rendering it verifies schema/revision, the exact `[open, acknowledged]` domain, `word_bits = 64`, the word-count formula, Alerts owner view, canonical acknowledgement action/slot, virtual-list capacity, row colors, detail glyph range, and tile equality with the existing cross-view transaction plan.

| Attack mode | Rejection condition |
|---|---|
| `abi` | Unsupported `acknowledged_row_state_plan` contract revision |
| `disable` | Required state plan replaced by `false` |
| `words` | `word_count != ceil(logical_capacity / 64)` |
| `owner` | Source owner differs from the canonical Alerts resident view |

## 5. Validation evidence

The final one-command regression exports standard and compact application-layer Scenes, runs the structural oracle, builds the Rust 1.87/wgpu 30 host, executes all four rejection cases, and then performs real X11/Vulkan input.

The exercised input sequence is Alerts first row acknowledgement, `PageDown`, `Home`, retained-row `Enter`, then Overview navigation. It establishes the following results:

1. The first acknowledgement logs `state=0=>1`, `ack-word=0`, and the first bit mask.
2. After recycling away and back, the host logs a recovered Alerts lane with `acknowledged=true`.
3. The repeated retained-row activation logs `reason=already-acknowledged` with zero state and GPU writes.
4. Overview displays the fixed eight-glyph count endpoint as `00000001`, proving no second increment occurred.
5. The existing rounded dual-application compatibility regression continues to pass.

The checked screenshots are retained under `out/acknowledged-row-state-evidence/`.

## 6. Explicit non-goals

This is not an unbounded record database, generalized status lattice, persistence layer, or free-form styling system. It does not implement cancel acknowledgement, batch actions, external synchronization, or serialized disk persistence. Those require a later bounded transaction-family plan and a separately proved persistence contract.

## 7. Reproduction

```bash
cd /home/ubuntu/noir_review/noir-racket-ui-statistical-analysis
bash tools/verify_acknowledged_row_state_executor_v1.sh
```

Expected final marker:

```text
ACKNOWLEDGED_ROW_STATE_EXECUTOR_V1_REGRESSION: PASS
```
