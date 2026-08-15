# Rust Digit Register Executor

## 实现结果

`wgpu-verify/src/bin/noir_winit_host.rs` 已从 Scene JSON 消费 Racket 编译器输出的 digit-register transition table。每个 focus slot 现在具有一个固定 `u32` pending register；Digit、Backspace 和 Escape 都只操作 compiler 已验证的固定数组、固定 integer arithmetic 与固定 GPU glyph offsets。

> Host 不保存字符串、不执行 UTF-8/十进制 parse、不通过 node ID 搜索 field，也不进行布局或 tile 几何计算。focus slot 是唯一索引；编译器在启动前已将该索引与 glyph storage、tile mask 和 register descriptor 绑定。

| 事件 | 运行时算术 | GPU/渲染动作 | 拒绝条件 |
|---|---|---|---|
| `digit-N` | `pending' = pending × radix + N` | 写当前 cursor 的固定 glyph ID cell；cursor 前进；标记 field tile | cursor 已满、`checked_mul/add` 溢出、结果大于 compiler maximum |
| Backspace | `pending' = pending / radix` | zero-fill 前一固定 glyph cell；cursor 后退；标记 field tile | cursor 为 0 |
| Escape | `pending = reset_value` | zero-fill field 的全部固定 glyph cells；cursor=0；标记 command/visual tile | 无 |

## Scene serde ABI

Rust 新增 `DigitRegister`，直接对应 compiler 的 `keyboard_map.fields[*].digit_register`：

```rust
#[derive(Debug, Deserialize)]
struct DigitRegister {
    radix: u32,
    max_digits: usize,
    initial_value: u32,
    reset_value: u32,
    maximum_value: u32,
}
```

`KeyboardTransition` 还读取 `register_op`、`register_radix` 与 `register_operand`。Host 先将其压缩为 `CompiledDigitRegister` 与 `CompiledKeyboardTransition`；运行时不再读取 JSON string。`Host` 自身仅保留：

```rust
keyboard_cursors: Vec<usize>,
keyboard_pending_values: Vec<u32>,
```

两个数组均以 compiler 固定的 focus slot 为下标，长度在启动期由 `CompiledKeyboardMap.fields.len()` 固定。

## 启动期 proof

`compiler_keyboard_map()` 在 wgpu 初始化前验证下列不变量：

| 对象 | proof |
|---|---|
| Field descriptor | `radix == 10`、`max_digits == max_chars`、`reset_value == 0`、`maximum_value == 10^max_chars - 1`、`initial_value <= maximum_value` |
| 每个 slot | 恰有 11 条 transition，且不存在重复 key |
| `digit-0..9` | `insert`、`advance`、glyph ID 等于 digit、`append-digit`、radix=10、operand=0..9 |
| Backspace | `backspace`、`retreat`、glyph ID=0、`drop-last`、radix=10、operand=0 |
| 所有 transition | tile mask 与 Focus Graph field mask 相等 |

通过后，Host 输出例如：

```text
compiler digit register: slot=1 field=alert-threshold-row$field \
  radix=10 digits=3 initial=72 reset=0 maximum=999
```

任何 ABI 偏差都会在创建窗口/开始事件循环前返回错误；不会把未证明的 opcode、radix 或 operand 留给输入期处理。

## 固定 executor

`Host::keyboard_transition()` 先复制当前 slot 的 `CompiledKeyboardField` 和 `CompiledKeyboardTransition`，然后只使用固定字段执行。

```rust
let next_pending = pending.checked_mul(transition.register_radix)
    .and_then(|value| value.checked_add(transition.register_operand));
let Some(next_pending) = next_pending.filter(|value| {
    *value <= field.digit_register.maximum_value
}) else {
    // reject: no glyph write, no cursor update, no tile submit
    return;
};
```

Backspace 使用已验证 radix 的整数除法。Escape 在现有 `keyboard_command()` 的 reset branch 中同步清空 glyph slots、cursor 与 pending value：

```rust
self.keyboard_cursors[slot] = 0;
self.keyboard_pending_values[slot] = field.digit_register.reset_value;
```

## 真实 X11/wgpu 验证

`tools/verify_settings_form.sh` 已扩展为真实 Xvfb/X11 输入序列：

```text
7 → Enter → Tab → 9 → 9(overflows) → Enter → Tab → 4 → Backspace → 4 → Escape
```

该 oracle 验证以下真实日志证据：

| slot | 行为 | 已验证 pending transition |
|---:|---|---|
| 0 | digit 7 | `5 → 57`，`append-digit radix=10 operand=7` |
| 1 | digit 9 | `72 → 729` |
| 1 | second digit 9 | `7299 > 999`，`register-overflow`，无 GPU write |
| 2 | digit 4 | `16 → 164` |
| 2 | Backspace | `164 → 16`，`drop-last radix=10` |
| 2 | digit 4 + Escape | `16 → 164 → 0`，field-local glyph zero-fill |

验证命令均通过：

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd .. && tools/verify_keyboard_command.sh && tools/verify_settings_form.sh
```

## 后续：Enter Commit

本阶段 pending register 已真实运行，但 Enter 仍执行已有 action plan，不会把 pending value 写回 user state。下一阶段应在 Racket 中新增受限 `commit-pending-register` Command Map kind；compiler 为 Enter 指定 target state 和 action/tile plan，Rust 则把 `keyboard_pending_values[slot]` 写入该 compiler-selected state，再复用已有 action/GPU patch executor。这样 `720 → Enter` 才成为真正的静态数值表单提交。

## References

实现与验证文件：`wgpu-verify/src/bin/noir_winit_host.rs`、`noir/ui/main.rkt`、`tools/verify_settings_form.sh`、`tools/verify_keyboard_command.sh`、`tests/run.rkt` 与 `wgpu-verify/out/settings-dashboard-e2e.log`。
