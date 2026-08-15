# Action Slot Lowering

## 结果概述

Noir 现在把 DSL action ID 降低为编译期固定的 **Action Slot index**。Racket 以 action ID 的字典序生成 canonical `action_slots`。Action Plan、Event Map 与 Keyboard Command Map 都携带同一 index；Rust 在窗口创建前证明每个 index 对应正确的 action ID、Action Plan、state-slot writes 与 tile plan。

> `Enter → action` 的事件期不再以 Enter 命令中的字符串选择 write plan。它使用 compiler-proved `action_index` 从 `compiled_actions: Vec<ActionPlan>` 取得 plan，并生成固定 winner write list。

## Canonical ABI

Racket runtime IR 新增：

```racket
(struct action-slot (index id) #:transparent)
(struct action-plan (id action-index writes gpu-updates instance-updates damage tile-ids) #:transparent)
(struct event-binding (slot node action action-index ... ) #:transparent)
(struct keyboard-command-transition
  (focus-slot key kind action action-index target-state target-state-index tile-ids)
  #:transparent)
```

`canonical-actions` 与 `action-index-by-id` 在 macro expansion 期间以 `symbol<?` 固定索引。以原 dashboard 为例：

| Action Slot | Action ID | 主要固定写入 |
|---:|---|---|
| 0 | `advance-progress` | throughput `size.x` instance field |
| 1 | `refresh-fps` | 3 个固定 glyph ID cells |
| 2 | `refresh-latency` | 3 个固定 glyph ID cells |

Settings showcase 的 apply actions 同样按字典序得到 `apply-alert-threshold=0`、`apply-batch-size=1`、`apply-sample-interval=2`；而 Event Map 可按用户声明顺序引用它们，因此 event slot 与 action slot 是两个明确分离的静态地址空间。

## Racket lowering

核心 compile-time table 为：

```racket
(define (canonical-actions actions)
  (sort actions symbol<? #:key c-action-id))

(define (action-index-by-id actions)
  (for/hash ([action (in-list (canonical-actions actions))]
             [index (in-naturals)])
    (values (c-action-id action) index)))
```

`noir-app` 计算 `action-indexes` 后将其传给 `compile-event-map`、`compile-action-plans` 和 `compile-keyboard-command-map`。因此 parser-only `form-row` 的 Apply button、基础 button Event Map、以及 text field 的 `#:on-enter action-id` 都在宏展开期确定 action address。

Scene JSON 继续保留 `actions` object 作为审计镜像，同时输出：

```json
"action_slots": [
  {"id":"apply-command", "index":0}
]
```

并在每个 action-dependent artifact 写入 `action_index`。普通 action Enter 使用该数值；commit Enter 与 Escape 的 `action_index` 必须为 JSON `null`。

## Rust admission 与执行

Rust 增加：

```rust
struct ActionSlot { index: usize, id: String }

// Host
action_slot_ids: Vec<String>,
compiled_actions: Vec<ActionPlan>,
```

`compiler_action_slots()` 在 startup 验证：

1. `action_slots` 覆盖并且只覆盖 Scene audit action map；
2. slot index 为稠密的 `0..N-1`；
3. action IDs 采用严格字典序；
4. action slot 的 index 等于相应 `ActionPlan.action_index`；
5. Event Map 的 `(action, action_index)` 一致。

Keyboard Command admission 还证明 action Enter 的 action name、`action_index`、Action Slot、Action Plan 与 field/action tile union 完全一致。事件期先调用 `action_write_plan_index(action_index)`，直接读取 `compiled_actions[action_index]` 并生成 compiler-fixed winner writes。日志包含 action index，例如：

```text
keyboard-command Enter: slot=0 field=command-field action=apply-command action_index=0 winner_writes=1 mask=0x0000000000000005
```

## 验证结果

| 验证层级 | 命令 | 结果 |
|---|---|---|
| Racket static oracle | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 0 个 `FAILURE` |
| Rust release | `cargo build --release --bin noir_winit_host` | 通过 |
| Settings X11/wgpu | `tools/verify_settings_form.sh` | 通过；commit/reset 均严格要求 `action_index:null` |
| Command X11/wgpu | `tools/verify_keyboard_command.sh` | 通过；Enter action 使用 `action_index=0` |

Racket oracle 额外验证 Settings action slot ID/order、Action Plan index、Event Map index、Command Map action index 与既有 state-slot proof 同时成立。

## Coalesced Batch 边界

`frame_coalesced_batches` 与 `frame_schedule` 当前保留 task/action ID 作为其既有 winner-write proof 的可审计 key；Host 对鼠标 activate batch 仍走该经过验证的 compatibility executor。直接 Enter action 的 plan selection 已使用 Action Slot array。下一步可把 batch 的 action task reference 降低为 `action_index`，使 coalesced executor 也摆脱 audit action map，完成 action path 的最终去字符串化。

## References

实现与验证文件：`noir/ui/main.rkt`、`wgpu-verify/src/bin/noir_winit_host.rs`、`tests/run.rkt`、`tools/verify_settings_form.sh`、`tools/verify_keyboard_command.sh`、`wgpu-verify/out/settings-dashboard-e2e.log` 与 `wgpu-verify/out/command-dashboard-keyboard-command-e2e.log`。
