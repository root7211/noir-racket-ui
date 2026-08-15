# 全路径 State Slot Lowering

## 结果概述

Noir 的状态依赖现在已经从 DSL state symbol 完整降低为 compiler-selected **State Slot index**。Racket 在宏展开期按照 state ID 的字典序生成 canonical `state_slots`；所有可变执行路径——按钮 action 的 state write、dynamic text glyph patch、progress instance patch、Focus Graph、Keyboard Map、Enter commit 与动态 glyph placement——均携带同一个固定 index。

> 运行时事件路径只对 `Vec<i64>` 做整数下标访问。state 名称仅作为 Scene 的可审计 metadata，在启动期与 slot table 交叉验证；不会参与输入、事件或 GPU patch 的查找。

## State Slot ABI

Racket runtime IR 新增：

```racket
(struct state-slot (index id initial) #:transparent)
```

`noir-app` 在扩展期通过 `canonical-states` 进行 `symbol<?` 排序，并输出：

```json
"state_slots": [
  {"id":"alert-threshold", "index":0, "initial":72},
  {"id":"batch-size",      "index":1, "initial":16},
  {"id":"sample-interval", "index":2, "initial":5}
]
```

| 编译产物 | 新字段 | 运行时用途 |
|---|---|---|
| `state_write` | `state_index` | `state_values[index] += delta` |
| `gpu_update` | `state_index` | 从固定 slot 生成动态 digit glyph IDs |
| `instance_update` | `state_index` | 从固定 slot 计算 `size.x` patch |
| `glyph_placement` | `state_index` / `null` | 证明 dynamic/static glyph 的状态归属 |
| `focus_entry` | `state_index` | Focus field 与其 editable value 的静态绑定 |
| `keyboard_field` | `state_index` | pending register 与 field state 的静态绑定 |
| `commit-pending-register` | `target_state_index` | Enter 提交的唯一 state destination |

## Racket lowering 结构

核心 compile-time helper 为：

```racket
(define (canonical-states states)
  (sort states symbol<? #:key c-state-id))

(define (state-index-by-id states)
  (for/hash ([state (in-list (canonical-states states))]
             [index (in-naturals)])
    (values (c-state-id state) index)))
```

`noir-app` 在 macro expansion 内构造 `state-indexes` 并传入 Glyph Placement、Focus Graph 和 Action Plan lowering。`action-plan->datum` 使 action 的三个可变 path 都收到相同 index：

```racket
(state-write 'submitted 2 'add 1)
(gpu-update 'text-run 'fps 'frame-rate 0 ...)
(instance-update 'instance-patch 'apply-progress 'submitted 2 ...)
```

`form-row #:on-enter commit` 输出 `target_state_index`，例如 `sample-interval` 固定为 `2`。Racket compiler 同时证明 target state、Focus entry state 与 commit tile mask 分别等于当前 field 的既定静态绑定和 tile。

## Rust admission 与执行

Rust Scene ABI 新增：

```rust
struct StateSlot { index: usize, id: String, initial: i64 }
```

启动期 `compiler_state_slots()` 证明 slot table：

1. slots 覆盖 debug `state` table；
2. indices 为稠密 `0..N-1`；
3. state IDs 为严格字典序；
4. 每个 slot 初值与 Scene debug state 初值相等。

`compiler_action_state_slots()` 随后逐条验证 action state write、GPU text patch 与 instance patch 的 `state_index` 和可审计 state ID 一致。Focus/Keyboard/Command/Glyph Placement admission 同样验证各自 index，不允许 host 接受只带名称、没有固定地址的 state-dependent artifact。

运行时 `Host` 的核心状态现在是：

```rust
state_slot_ids: Vec<String>,
state_slot_values: Vec<i64>,
initial_state_slot_values: Vec<i64>,
```

按钮 action 不再访问 `HashMap`：

```rust
let slot = self.state_slot_values
    .get_mut(state_write.state_index)
    .expect("startup proof validated index");
*slot += state_write.value;
```

text-run 与 instance patch 同样直接读取 `state_slot_values[update.state_index]`。Enter commit 使用预验证 `target_state_index` 写入同一个数组。因此 mouse action、keyboard commit 和 replay reset 共用同一无字符串状态 ABI。

## 真实验证

| 层级 | 验证命令 | 结果 |
|---|---|---|
| Racket | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 0 个 `FAILURE` |
| Rust | `cargo build --release --bin noir_winit_host` | 通过 |
| Settings X11/wgpu | `tools/verify_settings_form.sh` | 通过：`720` Enter commit、overflow reject、Backspace、Escape discard |
| Command X11/wgpu | `tools/verify_keyboard_command.sh` | 通过：action state-slot write 与 progress instance patch |

Command X11 oracle 的真实日志现在包含：

```text
state-slot write: action=apply-command state=submitted index=2 op=add value=3
instance-patch apply-progress state=submitted state_index=2: [536..540) size.x=0.337500
```

Settings X11 oracle 则证明 `sample-interval` 的 Enter target 是 `state_index=2`，且 `5 → Escape → 720 → Enter` 只提交 field tile 0。三行 field 的 slots、target indices 与 tiles 均彼此隔离。

## 兼容性边界

Scene 中仍保留 `state: { name: initial }` hash 作为可读 JSON 与启动期 parity proof。Host 的事件期不读取该 hash；任何后续 tool/export 可将其视作调试镜像。action map 仍按 action ID 定位，因为 Event Map 的 action dispatch 尚未进行 action-slot lowering；这与 state path 已经完成的数组化无关。

## 后续

下一步建议进行 **Action Slot Lowering**：为 Event Map、Frame Task 与 Keyboard action Command Map 引入 canonical action index，使 mouse/Enter action dispatch 也从 `HashMap<String, ActionPlan>` 变成 `Vec<CompiledActionPlan>` 的固定索引。这样状态、动作、GPU write plan 和 tile mask 将全部形成 compiler-addressed dense tables。

## References

实现与验证文件：`noir/ui/main.rkt`、`wgpu-verify/src/bin/noir_winit_host.rs`、`tests/run.rkt`、`examples/settings-dashboard.rkt`、`tools/verify_settings_form.sh`、`tools/verify_keyboard_command.sh`、`wgpu-verify/out/settings-dashboard-e2e.log` 与 `wgpu-verify/out/command-dashboard-keyboard-command-e2e.log`。
