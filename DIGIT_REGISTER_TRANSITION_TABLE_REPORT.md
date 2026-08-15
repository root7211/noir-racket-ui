# Digit Register Transition Table

## 目标与边界

本阶段把 `#lang noir/ui` 的 `keyboard-map` 从“只描述 glyph ID 写入”扩展为同时描述 **固定容量十进制 pending register** 的 transition table。每个数字 field 现在在宏展开期得到 radix、位宽、初始值、复位值、最大值，以及 digit / Backspace 对 pending integer 的固定算术操作。

> 本阶段完成的是 **Racket 编译器 IR、Scene JSON ABI 和静态证明**。现有 Rust Host 仍兼容地忽略新增字段，继续执行既有 glyph/tile path；下一阶段再让 Host 把这些常量实际写入 per-slot pending register，并让 Enter 选择 commit plan。

| 运行时工作 | 旧 keyboard-map | 新 keyboard-map |
|---|---|---|
| Digit glyph write | 固定 `glyph_id` 与 storage offset | 保持不变 |
| Cursor | `advance` / `retreat` | 保持不变 |
| Pending value | 无 compiler ABI | `value' = value * 10 + digit` |
| Backspace value | 无 compiler ABI | `value' = quotient(value, 10)` |
| 字符串解析 | 不适用 | **始终不存在** |

## Racket runtime IR

`noir/ui/main.rkt` 新增以下公开 runtime struct。它们会由宏展开生成纯数据 Scene，而不是留下解释器或 closure。

```racket
(struct digit-register
  (radix max-digits initial-value reset-value maximum-value)
  #:transparent)

(struct keyboard-field
  (focus-slot node state max-chars glyph-id-offsets tile-ids digit-register)
  #:transparent)

(struct keyboard-transition
  (focus-slot key kind glyph-id cursor-op tile-ids
              register-op register-radix register-operand)
  #:transparent)
```

对于一个 3 位 field，compiler 输出固定 descriptor：

```racket
(digit-register 10 3 initial-state-value 0 999)
```

其中 `initial-state-value` 直接来自 `noir-app` 的 `(state [name integer] ...)` 声明；如果它为负数或大于 `999`，宏展开立即失败。因而 field 容量与初始 pending 值无法在运行时漂移。

## 编译期 transition table

`compile-keyboard-map` 现在接收 `state-initial-by-id`，为每个 Focus Graph entry 生成 11 条 transition。每个 transition 仍携带既有 glyph ID、cursor op 和 tile IDs，同时携带 register arithmetic。

| key | glyph/cursor | register op | radix | operand | pending-value 语义 |
|---|---|---|---:|---:|---|
| `digit-0` … `digit-9` | 写 glyph `0` … `9`，`advance` | `append-digit` | 10 | 0 … 9 | `v' = v × 10 + d` |
| `backspace` | zero glyph，`retreat` | `drop-last` | 10 | 0 | `v' = quotient(v, 10)` |

核心 lowering 结构如下。

```racket
(define register (c-digit-register 10 max-digits initial-value 0 maximum-value))

(c-keyboard-transition slot (string->symbol (format "digit-~a" digit))
                       'insert digit 'advance tile-ids
                       'append-digit 10 digit)

(c-keyboard-transition slot 'backspace 'backspace 0 'retreat tile-ids
                       'drop-last 10 0)
```

compiler 随后证明：每个 field 恰有十条 `append-digit` 和一条 `drop-last`；十条 operand 严格为 `0..9`；全部 radix 均为 10；最大值严格为 `10^max-digits - 1`；初始值位于 `[0, maximum-value]`；每条 transition 的 tile IDs 与 field tile IDs 相同。

## Scene JSON ABI

`keyboard_map.fields[*]` 新增 `digit_register`，`keyboard_map.transitions[*]` 新增三个 register 字段。例如 Settings showcase 的 sample interval field：

```json
{
  "digit_register": {
    "initial_value": 5,
    "max_digits": 3,
    "maximum_value": 999,
    "radix": 10,
    "reset_value": 0
  }
}
```

其 `digit-7` transition 为：

```json
{
  "key": "digit-7",
  "kind": "insert",
  "cursor_op": "advance",
  "register_op": "append-digit",
  "register_radix": 10,
  "register_operand": 7
}
```

由于 Rust `serde` 默认忽略未知 Scene 字段，当前 Host 保持向后兼容；这使 Racket ABI 可以先独立验证，再在下一阶段启用 Host 的 pending register executor。

## 静态验证

`tests/run.rkt` 已增加以下 oracle：

| oracle | 验证内容 |
|---|---|
| Focus dashboard | 两个 3-digit register 的 initial values 为 `34`、`12`，maximum 都为 `999` |
| Transition canonicality | 十条 `append-digit` 的 operands 严格为 `0..9`，Backspace 为 `drop-last` |
| JSON ABI | `digit_register`、`register_op`、`register_radix`、`register_operand` 字段稳定输出 |
| Settings form | 三个 register initial values 为 `5`、`72`、`16`，各自独立且 reset 均为 `0` |
| Compatibility | 既有 Command Map 和 Settings X11/wgpu scripts 可读取扩展 Scene 并通过 |

执行结果：`PLTCOLLECTS="$PWD:" racket tests/run.rkt` 为 **0 个 `FAILURE`**；`cargo build --release --bin noir_winit_host`、`tools/verify_keyboard_command.sh` 与 `tools/verify_settings_form.sh` 均通过。

## 下一阶段

下一步将 Rust `CompiledKeyboardField` 扩展为 `CompiledDigitRegister`，并在 `keyboard_transition()` 中执行已编译的 `append-digit` / `drop-last` 算术与 overflow reject。随后再将 Enter command 从演示 action 扩展为 `commit-pending-register`：把该 slot 的 pending integer 写入 compiler-selected target state，再执行既定 glyph/instance/tile write plan。

## References

实现和验证位于仓库内：`noir/ui/main.rkt`、`tests/run.rkt`、`examples/settings-dashboard.rkt`、`tools/verify_keyboard_command.sh`、`tools/verify_settings_form.sh`、`out/settings-dashboard.scene.json`。
