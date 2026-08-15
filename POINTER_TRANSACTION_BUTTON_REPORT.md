# Pointer-triggered Static Transaction Buttons

## Completed capability

The UI language now includes a parser-only transaction button:

```racket
(transaction-button #:id apply-all-button
                    #:transaction apply-all
                    #:operation commit
                    #:width 180 #:height 12
                    "Apply All")

(transaction-button #:id reset-all-button
                    #:transaction apply-all
                    #:operation reset
                    #:width 180 #:height 12
                    "Reset All")
```

`transaction-button` disappears during macro expansion. It lowers to the established base `button` node plus static compiler metadata. There is no runtime component type, form registry, dynamic transaction lookup, or action-name fallback.

## Compiler ABI

A normal button emits an Action Slot address. A transaction button emits exactly one mutually exclusive dispatch descriptor:

| Event field | Apply All | Reset All |
|---|---:|---:|
| `action` / `action_index` | `null` / `null` | `null` / `null` |
| `transaction_op` | `commit` | `reset` |
| `transaction_index` | `0` | `0` |
| transaction ID | `apply-all` | `apply-all` |

The same transaction table already proves the member pairs and group mask:

```text
field_slots   = [0, 1, 2]
state_indices = [2, 0, 1]
tile_ids      = [0, 1, 2]
```

The compiler also creates a fixed `transaction-0` frame task. Activate batches use tagged refs, so release animation and business dispatch are auditable as `Transient(slot) → Transaction(0)`. Transaction tasks are excluded from the transient task table and cannot be accidentally dispatched as a visual task.

## Rust execution

Startup admission accepts an Event Map entry only if it is either an Action Slot binding or a transaction binding; mixed and incomplete metadata are rejected. Transaction batch refs must name `transaction-<index>`, point to a `FrameTask(kind="transaction")`, and match the dense transaction table.

On pointer activation, the host first consumes the compiler-selected activate batch, including the release visual and `CompiledTaskRef::Transaction(index)`. Business mutation then uses the same already-proved transaction index.

For `commit`, the executor stages every `(field_slot, state_index, pending_value)` pair, validates all values before mutation, then writes `state_slot_values[state_index]` in compiler order. For `reset`, it writes no committed state. It loops only over the compiler-fixed field slot vector, zeros each field's preallocated glyph cells, resets the fixed cursor and pending register, then marks the transaction tile union.

## Real X11/wgpu evidence

`tools/verify_pointer_transactions.sh` performs real X11 keyboard editing followed by real mouse clicks on the 640×360 host surface.

1. Pending registers are prepared as `720`, `729`, and `164`; `7299` is rejected by the fixed digit-register maximum.
2. A click at the compiler-proven Apply All rect executes `apply-all`, atomically writing `state_slot[2]=720`, `state_slot[0]=729`, and `state_slot[1]=164`.
3. A click at the Reset All rect resets all three pending registers/glyph ranges/cursors to zero while reporting `state_writes=0`.
4. The host logs both `Transaction(0)` activate-batch evidence and exact group tile mask `0x7`.

The full Racket regression, Rust release build, and the pointer X11/wgpu oracle pass.

## Reproduction

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd ..
tools/verify_pointer_transactions.sh
```

## Next boundary

The next GUI-primitives step is an editable ASCII letter path using the existing page-1 atlas. It should keep the same architecture: a compile-time alphabet transition table, fixed glyph cells, digit-register-compatible pending storage policy, and the same State/Action/Transaction slot model.
