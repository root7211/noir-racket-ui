# Compiler-Selected `commit-pending-register`

## 完成内容

`#lang noir/ui` 现在支持在数字 field 上声明 `#:on-enter commit`。该标记不会调用 action ID，也不会让 Rust 根据 state 名称进行查找；Racket 编译器把 Enter 降低为 `kind: "commit-pending-register"`，把 field 自己已绑定的 state 作为 `target_state`，并证明 Enter tile mask 精确等于该 field tile。

Rust Host 在启动期验证 `target_state` 与 Focus Graph/Keyboard Map field state 一致，再将它压缩为排序 compiler state table 的固定 index。Enter 发生时只读取 `keyboard_pending_values[focus_slot]`、写入 `state_slot_values[target_index]` 与镜像 state map，并提交 compiler 给定的 tile mask。

> **运行时没有 state-name lookup、widget lookup、字符串解析、动态 damage union 或布局计算。** `target_state` 只出现在 Scene admission 阶段；事件期仅使用两个整数：focus slot 和 target state index。

## 1. Racket DSL 与宏展开

基础 `text-field` 现在接受保留 Enter symbol `commit`：

```racket
(text-field #:id sample-field
            #:state sample-interval
            #:max-chars 3
            #:tab-index 0
            #:on-enter commit)
```

`form-row` 扩展为分离键盘 Enter 与鼠标 Apply action：

```racket
(form-row #:id sample-interval-row
          #:label "SAMPLE INTERVAL"
          #:state sample-interval
          #:max-chars 3
          #:tab-index 0
          #:on-enter commit
          #:on-apply apply-sample-interval)
```

`#:on-apply` 被省略时，button action 保持旧行为，即与 `#:on-enter` 相同。显式分离后，Enter 走 pending register commit；Apply button 仍可走已有 event/action plan。两者都在 macro expansion 中内联为既有 `row/text/text-field/button` primitives。

## 2. Compiler Command Map ABI

runtime IR 现在是：

```racket
(struct keyboard-command-transition
  (focus-slot key kind action target-state tile-ids)
  #:transparent)
```

对于 `#:on-enter commit`，`compile-keyboard-command-map` 输出：

```json
{
  "focus_slot": 0,
  "key": "enter",
  "kind": "commit-pending-register",
  "action": null,
  "target_state": "sample-interval",
  "tile_ids": [0]
}
```

编译器证明以下条件：commit 没有 action；target state 等于 focus field 的 compile-time state binding；tile IDs 精确等于 field tile IDs。旧 action Enter 则仍要求 `target_state: null`，且 tile IDs 为 field/action union；Escape 同时要求 `action: null` 与 `target_state: null`。

| Enter kind | action | target state | tile mask |
|---|---|---|---|
| `action` | 已声明 action ID | `null` | field ∪ action |
| `commit-pending-register` | `null` | field state | field |
| Escape `reset` | `null` | `null` | field |

## 3. Rust admission 与固定 executor

Rust JSON ABI 为：

```rust
struct KeyboardCommandTransition {
    focus_slot: usize,
    key: String,
    kind: String,
    action: Option<String>,
    target_state: Option<String>,
    tile_ids: Vec<usize>,
}
```

启动期 `compiler_keyboard_command_map()` 对 commit 的关键逻辑如下：

```rust
anyhow::ensure!(target_state == scene.focus_graph.entries[slot].state,
                "commit target state must equal compiler field state");
let target_state_index = *state_index_by_id.get(&target_state)?;
anyhow::ensure!(enter_mask == field.tile_mask,
                "commit Enter tile mask must equal field tile mask");
```

state table 以编译器 state IDs 的字典序固定。宿主和 admission 使用同一种排序，因此 `target_state_index` 是稳定且已验证的 runtime address。事件期只执行：

```rust
let state_index = command.target_state_index.expect("validated at startup");
let committed_value = i64::from(self.keyboard_pending_values[slot]);
self.state_slot_values[state_index] = committed_value;
self.state.insert(self.state_slot_ids[state_index].clone(), committed_value);
```

这里的 `HashMap` 写入是现有 state/action ABI 的兼容镜像；commit 的**选择**不依赖它：state slot 已在启动时固定。后续可以将 action state write 也统一压缩为 state index，从而消除镜像 map。

## 4. System Settings 实验

Settings showcase 的三行字段均为 `#:on-enter commit`：

| slot | field | target state | state index | tile |
|---:|---|---|---:|---:|
| 0 | `sample-interval-row$field` | `sample-interval` | 2 | 0 |
| 1 | `alert-threshold-row$field` | `alert-threshold` | 0 | 1 |
| 2 | `batch-size-row$field` | `batch-size` | 1 | 2 |

真实 Xvfb/X11 input sequence 为：

```text
Escape → 7 → 2 → 0 → Enter → Tab → 9 → 9(overflows) → Enter → Tab → 4 → Backspace → 4 → Escape
```

真实 wgpu host 日志 oracle 验证：

```text
slot=0 ... committed=5->720 mask=0x0000000000000001
slot=1 ... pending=729 ... second 9 register-overflow ... committed=72->729
slot=2 ... pending=164->16 via Backspace ... Escape pending=164->0
```

因此该实验同时证明 commit、value overflow reject、Backspace inverse、Escape discard、Tab isolation 和 field-local tile submission。

## 5. 验证结果

| 层级 | 验证 | 结果 |
|---|---|---|
| Racket | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 0 个 `FAILURE` |
| Rust | `cargo build --release --bin noir_winit_host` | 通过 |
| X11/wgpu | `tools/verify_settings_form.sh` | 通过，包含 `720` commit oracle |
| Legacy X11/wgpu | `tools/verify_keyboard_command.sh` | 通过，验证 action Enter ABI 兼容 |

## 6. 后续方向

下一步应将 state/action GPU patch plan 也 lowering 为 **state slot index**，使 action paths 与 commit paths 一样不再持有 runtime state name。之后可支持 compiler-proven multi-field form transaction：多个 commit slot 以固定 dependency order 写入 state slots，并以静态 conflict graph 证明它们不会重叠。

## References

实现与验证文件：`noir/ui/main.rkt`、`examples/settings-dashboard.rkt`、`tests/run.rkt`、`wgpu-verify/src/bin/noir_winit_host.rs`、`tools/verify_settings_form.sh`、`tools/verify_keyboard_command.sh`、`wgpu-verify/out/settings-dashboard-e2e.log`。
