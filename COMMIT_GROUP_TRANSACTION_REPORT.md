# Multi-field Static Transaction: `commit-group` / `apply-all`

## Result

`#lang noir/ui` now supports a compiler-defined multi-field transaction declaration:

```racket
(commit-group apply-all sample-interval alert-threshold batch-size)
```

A text field may use the transaction identifier as its existing `#:on-enter` literal:

```racket
(form-row #:id sample-interval-row
          #:state sample-interval
          #:max-chars 3
          #:tab-index 0
          #:on-enter apply-all
          #:on-apply apply-sample-interval
          ...)
```

No runtime form schema, state-name lookup, transaction map lookup, sorting, layout operation, or parsing is introduced. `form-row` and `settings-form` still disappear during macro expansion.

## Racket compile-time ABI

The compiler parses each `commit-group` only when all member state IDs are declared, unique syntax literals. It sorts transaction IDs lexically to create a dense canonical transaction table, then resolves every declared state to the unique editable field binding in the Focus Graph.

```racket
(struct transaction-plan
  (index id field-slots state-indices tile-ids)
  #:transparent)
```

The System Settings transaction is lowered as:

| Artifact | Compiler-fixed value |
|---|---|
| Transaction ID | `apply-all` |
| Transaction index | `0` |
| Field slots | `[0, 1, 2]` |
| State slots | `[2, 0, 1]` |
| Tile union | `[0, 1, 2]` |

Every member field receives the same Enter command:

```json
{
  "kind": "commit-group",
  "transaction_index": 0,
  "tile_ids": [0, 1, 2]
}
```

The compiler rejects duplicate transaction members, undeclared states, states without editable field bindings, duplicate field/state slots, or an Enter transaction that does not contain the current focus slot.

## Rust admission and executor

Rust deserializes the transaction table to `TransactionPlan`, then builds one `CompiledTransactionPlan` per compiler index. Startup admission proves lexical/dense index order, at least two member fields, one-to-one field/state pairs, unique field and state slots, field-to-state binding parity with the Keyboard Map, and exact transaction tile mask.

```rust
struct CompiledTransactionPlan {
    id: String,
    field_slots: Vec<usize>,
    state_indices: Vec<usize>,
    tile_mask: u64,
}
```

When `commit-group` is pressed, the host performs two predetermined passes. The **admission pass** reads all `pending_value[field_slot]` entries and validates each value against its compiler-proven digit register maximum before mutating state. The **commit pass** then writes the staged values in the compiler-specified pair order:

```rust
state_slot_values[state_index] = pending_value[field_slot];
```

If one admission check fails, the executor returns before the commit pass: there are no state writes and no GPU writes. In the valid path, transaction state mutation is atomic with respect to this event: there is no interleaved runtime dispatch point between staging and commit.

## Real X11/wgpu verification

`tools/verify_settings_form.sh` launches Xvfb and the release winit/wgpu host. It performs actual keyboard input in three static fields:

1. Slot 0: `Escape`, `7`, `2`, `0`, giving pending value `720`.
2. Slot 1: `9`, `9`; initial `72` becomes `729`, while the second digit attempt is rejected because `7299 > 999`.
3. Slot 2: `4`, `Backspace`, `4`, giving pending value `164`.
4. `Return` on slot 2 executes `apply-all` once.
5. `Escape` then resets only slot 2, proving group commit does not broaden discard scope.

The host log proves one transaction event with:

```text
commits=[field_slot=0:state_index=2:5->720,
         field_slot=1:state_index=0:72->729,
         field_slot=2:state_index=1:16->164]
mask=0x0000000000000007
```

The same run verifies digit register overflow rejection, local glyph/cursor reset, and exact group tile union. Racket static regression and Rust release build also pass.

## Reproduction

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd ..
tools/verify_settings_form.sh
```

## Boundary

This implementation gives a keyboard-triggered static transaction. Each row’s pointer Apply button intentionally remains an independent Action Slot path, which provides a live comparison between singleton action and multi-field transaction execution. A future `#:apply-all-button` macro can lower a dedicated pointer button to the same transaction index without changing transaction semantics or state addressing.
