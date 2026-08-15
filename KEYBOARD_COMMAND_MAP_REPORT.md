# Keyboard Command Map：Enter / Escape 的编译期命令降低

**阶段状态：完成并验证。** 本阶段为 `#lang noir/ui` 的固定容量 `text-field` 增加了两个高层命令：`Enter` 可静态绑定到一个已声明 action，`Escape` 则始终降低为当前 field 的固定 glyph-slot reset。目标不是在运行时解释“提交”或“取消”，而是在宏展开与 Scene lowering 时将键、焦点槽位、state 写入、GPU 字节地址和待重绘 tile 一并确定。宿主收到键盘事件后只在已验证的小型数组中选择分支。

> **运行时契约：** Enter/Escape 不执行布局、文本 shaping、glyph atlas 查询、tile 求交、action 名解析或 damage region 合并。它们只消费编译器输出的 command transition、预分配 glyph/storage 地址、action write plan 和 bitmask tile selection。

| 组件 | 编译期确定的内容 | 运行时允许的工作 |
|---|---|---|
| DSL `text-field` | `#:on-enter` action、`#:on-escape reset`、field state、焦点 slot | 无 DSL 解析 |
| Command Map | `focus_slot × {enter, escape}` transition、kind、action、tile IDs | 以 slot 索引已编译数组 |
| Enter | field tile ∪ action tile、action winner-write plan | 状态加法和固定 buffer writes |
| Escape | 当前 field 的 glyph ID offsets 与 field tile | 对既定 32-bit glyph ID cells zero-fill |
| 渲染 | tile mask、glyph packet subrange、placement geometry | 提交预选 tile，不重新 cull/layout |

## 1. DSL 与编译期 IR

`text-field` 现在接受下列受限命令元数据。`on-enter` 只能引用同一 `noir-app` 中的字面 action ID；`on-escape` 当前固定为 `reset`。二者都不是动态回调，也不接收闭包。

```racket
(text-field #:id command-field
            #:state command-value
            #:max-chars 3
            #:tab-index 0
            #:width 240
            #:on-enter apply-command
            #:on-escape reset)
```

编译器产生 `keyboard-command-map`，其中每个 focus slot 必有一条 Escape reset transition，而 Enter transition 仅在 field 显式带有 `#:on-enter` 时出现。`command-dashboard.rkt` 产生的确定性表如下。

| focus slot | field | key | kind | action | tile IDs |
|---:|---|---|---|---|---|
| 0 | `command-field` | `enter` | `action` | `apply-command` | `[0, 2]` |
| 0 | `command-field` | `escape` | `reset` | none | `[0]` |
| 1 | `query-field` | `escape` | `reset` | none | `[1]` |

Enter 的 `[0, 2]` 不是在 Host 合并而来；它是 compiler 直接输出的 field tile `[0]` 与 `apply-command` action tile `[2]` 的已证明并集。相反，Escape 的 tile IDs 必须严格等于 field tile IDs，因此取消编辑永远不会触发无关 action tile。

Scene JSON 使用 `action: null` 表示无 action；Racket IR 内部仍使用 `#f`。这一 ABI 区分了“无命令绑定”与 JSON boolean `false`，使 Rust `Option<String>` 能无歧义反序列化。

## 2. 启动期 proof 与 Rust 固定执行器

`noir_winit_host` 在读取 Scene 后将 JSON map 预编译为按 focus slot 索引的 `CompiledKeyboardCommandMap`。启动期 proof 强制下列不变量：

| 不变量 | Host proof | 失败处理 |
|---|---|---|
| 每个可编辑 slot 有且仅有一个 Escape | 查找 `key == "escape"` | 拒绝 Scene |
| Escape 不是 action | `kind == reset` 且 `action == None` | 拒绝 Scene |
| Escape 局部性 | `escape_mask == field.tile_mask` | 拒绝 Scene |
| Enter 引用真实 action | action ID 必须存在于 `scene.actions` | 拒绝 Scene |
| Enter 并集正确 | `enter_mask == field_mask | action_mask` | 拒绝 Scene |
| command key 集受限 | 只接收 `enter` 与 `escape` | 拒绝 Scene |

事件期函数 `keyboard_command()` 从当前焦点 slot 读取已编译 transition。Enter 调用既有的 `action_write_plan()` 和 `apply_action_winner_writes()`，因此复用了 compiler 给出的固定 glyph/instance write range。Escape 迭代该 field 的预分配 `glyph_id_offsets`，向每个 cell 的第一个 `u32` 写入 `0`，随后把 cursor 固定为 `0`。两条路径随后只 OR command tile mask 与既有 caret/placeholder visual mask，再提交已有 tile renderer。

本阶段还移除了 Host 对名为 `progress` 的隐式状态假设。Rust `InstanceUpdate` 现在完整消费 compiler JSON 的 `node`、`state`、`byte_length` 和 `field`，并只接受 `size.x`、4-byte 的 instance patch。因此 `apply-command` 正确从 `submitted` state 写入 `apply-progress` 的固定 size.x 地址 `[536..540)`，而不是误读一个全局特例名称。

## 3. 真实 X11 / wgpu 执行验证

验证脚本 `tools/verify_keyboard_command.sh` 使用 Xvfb、winit X11 窗口和 wgpu 宿主。它不直接调用 Rust executor，而是通过 `xdotool` 注入以下真实键盘事件序列：`5 → Enter → 3 → Escape`。脚本同时校验导出的 JSON、启动期 proof 和运行时日志。

| 验证步骤 | 观测到的结果 | 说明 |
|---|---|---|
| Scene admission | slot 0 Enter mask `0x5`；Escape masks `0x1`/`0x2` | compiler command table 通过 Rust proof |
| 数字 `5` | 写 `[544..548)` 为 glyph ID `5` | 固定容量 field 的既定 cell 写入 |
| Enter | `event-map dispatch: apply-command` | action 被固定 ID 分派 |
| Enter instance write | `apply-progress state=submitted: [536..540) size.x=0.337500` | 状态到 size.x 的固定 4-byte patch |
| Enter redraw | mask `0x5`，提交 tile 0 与 tile 2 | field/action 预计算 tile 并集生效 |
| 数字 `3` | 写 `[576..580)` 为 glyph ID `3` | cursor `1 → 2` 的固定 cell 写入 |
| Escape | zero-fill offsets `[544, 576, 608]` | 无 action、无 layout，仅重置本 field 三个 glyph cells |
| Escape redraw | mask `0x1`，仅提交 tile 0 | reset 的 field-local tile proof 生效 |

日志位于 `wgpu-verify/out/command-dashboard-keyboard-command-e2e.log`。在 Xvfb 环境中可预期出现 DRI3/EGL 警告；验证仍通过 wgpu 的实际 renderer command submission、tile renderer 与 timestamp-query-capable adapter 路径执行。该实验断言的是框架的真实 X11 输入和 wgpu 宿主路径，而非对物理显示服务器的性能结论。

## 4. 回归 oracle

`tests/run.rkt` 已引入 `command-dashboard.rkt`，并从 compiler runtime IR 与 `scene->jsexpr` 两个层面验证：

1. command transition 顺序为 `Enter(slot 0) → Escape(slot 0) → Escape(slot 1)`；
2. Enter 的 action 恰为 `apply-command`，tile IDs 恰为 `[0, 2]`；
3. `command-field` 的 Escape tile IDs 恰为 `[0]`；
4. 没有 `query-field` Enter transition，且其 Escape tile IDs 恰为 `[1]`；
5. JSON 中 Escape action 恰为 `null`，与 Rust `Option<String>` ABI 一致。

此外，回归文件修复了 component/repeat 的“存在即真”断言形式，并把 Focus/Text Field Visual 的固定 instance/glyph offsets 同步到当前 lowering ABI 快照。最终运行以 `0` 个 `FAILURE` 完成。

## 5. 可复现实验

在项目根目录 `/home/ubuntu/noir_review/noir-racket-ui` 执行：

```bash
# 1. 构建 X11/wgpu 宿主（Rust 1.75 兼容目标）
cd wgpu-verify
cargo build --release --bin noir_winit_host
cd ..

# 2. 执行全部 Racket IR regression；RackUnit check 失败不一定会使 Racket 返回非零，故显式计数
PLTCOLLECTS="$PWD:" racket tests/run.rkt > /tmp/noir-racket-regression.log 2>&1
! grep -q '^FAILURE' /tmp/noir-racket-regression.log

# 3. 导出 Command scene，并驱动真实 Xvfb/X11 keyboard 输入
./tools/verify_keyboard_command.sh
```

最终验证状态如下。

| 项目 | 命令或 oracle | 结果 |
|---|---|---|
| Rust release build | `cargo build --release --bin noir_winit_host` | 通过 |
| Racket 全量 regression | `PLTCOLLECTS="$PWD:" racket tests/run.rkt`，`FAILURE=0` | 通过 |
| Scene export | `command-dashboard.scene.json` 含 3 条 command transition | 通过 |
| X11 Enter/Escape | `tools/verify_keyboard_command.sh` | 通过 |

## 6. 修改清单与后续边界

| 文件 | 本阶段变化 |
|---|---|
| `noir/ui/main.rkt` | `text-field` command lowering、Command Map IR/JSON 与 `action:null` ABI |
| `examples/command-dashboard.rkt` | command field Enter→apply-command、query field Escape-only showcase |
| `wgpu-verify/src/bin/noir_winit_host.rs` | Command Map admission proof、fixed executor、state-driven instance patch |
| `tests/run.rkt` | Command Map IR/JSON oracle 与更新后的 Focus snapshots |
| `tools/verify_keyboard_command.sh` | Xvfb/xdotool/wgpu end-to-end oracle |

下一步建议继续保持“组合组件仍然在宏展开期消失”的主线：先实现 `form-row` / `settings-form` 内联组件，使 `label + text-field + button` 仍降低为同一套 fixed focus, keyboard, command, tile 与 instance plans。此后再考虑扩展 A–Z 输入字符集；已有 page-1 ASCII atlas 可以复用，但必须同样把字符到 glyph ID、cell 地址和 transition table 在编译期固定。

## References

本报告的断言均来自仓库内可复现实现与实验日志，而非外部资料：`noir/ui/main.rkt`、`wgpu-verify/src/bin/noir_winit_host.rs`、`examples/command-dashboard.rkt`、`tests/run.rkt`、`tools/verify_keyboard_command.sh` 以及 `wgpu-verify/out/command-dashboard-keyboard-command-e2e.log`。
