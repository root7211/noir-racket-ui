# `form-row` / `settings-form`：编译期表单组合与 Rust 宿主结构

## 结论

`form-row` 与 `settings-form` **不应在 Rust 中拥有 `FormRow`、`SettingsForm`、`Widget` 或动态表单 registry 类型**。它们是 `#lang noir/ui` 的编译期组合语法；在 Racket 宏展开阶段即消失，降低为已有的 `column`、`row`、`text`、`text-field` 与 `button`。因此 Rust/wgpu 宿主不新增任何“表单解释器”，仍以同一份 `Scene JSON`、`FocusGraph`、`KeyboardMap`、`KeyboardCommandMap`、Action Plan 与 Tile Plan 执行。

> **设计边界：** Racket 决定组合、静态 ID、几何、焦点顺序、键盘命令和 tile；Rust 只验证 Scene ABI 并对固定 buffer offsets 执行写入/提交。将 form-row 变成 Rust runtime 类型会重新引入运行时树遍历、name lookup 和布局语义，违背本项目的编译型目标。

| 层次 | `form-row` / `settings-form` 的职责 | 运行时对象 |
|---|---|---|
| Racket `begin-for-syntax` | 解析受限参数、派生稳定 ID、生成基础 node datum | 无 |
| Scene lowering | 生成 layout、glyph placement、focus/key/command/tile/action plans | 纯 JSON 数组与固定整数 |
| Rust admission | 验证 focus slot、action 引用、Enter union、Escape locality | `Compiled*` 固定数组 |
| wgpu event loop | 用 slot 查询 transition，写既定 buffer range，提交既定 tile mask | 无 form/widget 分派 |

## 1. 已实现的 Racket 编译期结构

实现位于 `noir/ui/main.rkt` 的 `begin-for-syntax` 区域。`parse-form-row` 接受单行 label、固定容量数字 field、Enter action 和 Apply button，并生成三个稳定派生 ID：`$label`、`$field`、`$apply`。它还把 row 高度显式固定为 **46px**，保证由现有静态 layout solver 推导的 button、text-field clip 与 scissor 均位于 640×360 原型 viewport 内。

```racket
;; 用户 DSL
(form-row #:id sample-interval-row
          #:label "SAMPLE INTERVAL"
          #:state sample-interval
          #:max-chars 3
          #:tab-index 0
          #:on-enter apply-sample-interval)

;; 宏展开后的基础节点结构
(row #:id sample-interval-row #:height 46 #:gap 12
  (text #:id sample-interval-row$label #:width 176 "SAMPLE INTERVAL")
  (text-field #:id sample-interval-row$field
              #:state sample-interval
              #:max-chars 3
              #:tab-index 0
              #:placeholder "VALUE"
              #:on-enter apply-sample-interval
              #:on-escape reset
              #:width 180)
  (button #:id sample-interval-row$apply
          #:width 88
          "Apply"
          #:on apply-sample-interval))
```

`text-field` 随后沿用原有 lowering：它继续展开为 `stack + focus overlay + placeholder text + dynamic text + caret overlay`。因此表单代码本身不承担 glyph atlas、caret、placeholder、Focus Graph、Keyboard Map 或 Command Map 逻辑；这些均由已经存在的基础 primitive lowering 自动生成。

`parse-settings-form` 的输入被故意限制为字面 `form-row` 子项。它只生成一个基础 `column`，并拒绝任意 runtime child、schema、lambda 或通用对象。由此，行数量、tab order、child IDs 及整个静态 node graph 都在宏展开时确定。

```racket
(settings-form #:id system-settings #:gap 8 #:padding 8 #:background dark
  (form-row ...)
  (form-row ...)
  (form-row ...))

;; 降低为
(column #:id system-settings #:gap 8 #:padding 8 #:background dark
  (row ...)
  (row ...)
  (row ...))
```

## 2. 必要的编译器 tile fallback

键入数字直接改写 field 的 glyph ID cells，因此每个 focusable field 必须存在一个固定 tile，即使 Enter action 只修改其他状态。`compile-render-schedules` 现加入受限 fallback：如果 field rect 不与既有 action text damage、instance damage 或 button event rect 相交，编译器才用该 field 的 **已知 layout rect** 追加 tile candidate。

这不是运行时求交。参与判断的所有内容都是编译期 `c-layout` 与 `c-rect` 数据；而已覆盖的旧 Scene 不会新增 rect，故其 tile 顺序与 tile ID 保持稳定。它消除了早期“必须额外声明 refresh action，才能给 field 取得 tile”的原型限制。

## 3. Rust：应有的通用结构，而非 Form 类型

Rust 文件 `wgpu-verify/src/bin/noir_winit_host.rs` 无需、也不应新增 `FormRow` 或 `SettingsForm`。关键 ABI 是通用的 Command Map 与 Keyboard Map。Settings showcase 降低出来的数据直接进入以下现有结构。

```rust
#[derive(Debug, Default, Deserialize)]
struct KeyboardCommandMap {
    #[serde(default)]
    transitions: Vec<KeyboardCommandTransition>,
}

#[derive(Debug, Deserialize)]
struct KeyboardCommandTransition {
    focus_slot: usize,
    key: String,                 // "enter" | "escape"
    kind: String,                // "action" | "reset"
    #[serde(default)]
    action: Option<String>,      // JSON null -> None
    #[serde(default)]
    tile_ids: Vec<usize>,
}

struct CompiledKeyboardField {
    node: String,
    max_chars: usize,
    glyph_id_offsets: Vec<u64>,
    tile_mask: u64,
}

struct CompiledKeyboardCommandTransition {
    kind: KeyboardCommandKind,
    action: Option<String>,
    tile_mask: u64,
}
```

启动期函数 `compiler_keyboard_command_map()` 把 JSON transition 验证并压缩到 `Vec<Vec<CompiledKeyboardCommandTransition>>`：外层 index 是 compiler 固定的 focus slot，内层最多是 Escape reset 与可选 Enter action。它检查 Escape mask 等于 field mask，并检查 Enter mask 恰等于 `field_mask | action_mask`。这些检查对一个裸 `text-field` 和 form-row 内联出的 `$field` 完全相同。

运行时路径也没有 form 特例。`Host::keyboard_command()` 从当前 focus slot 取得 transition；Enter 调用既有 `action_write_plan()` 与 `apply_action_winner_writes()`；Escape 遍历 `glyph_id_offsets` 向 glyph buffer 的既定 `u32` cells 写零；最后执行 `mark_dirty_tiles(command.tile_mask | visual_mask, ...)`。对应结构如下。

```rust
match command.kind {
    KeyboardCommandKind::Action => {
        let action = command.action.as_ref().expect("validated at startup");
        let writes = self.action_write_plan(action)?;
        self.apply_action_winner_writes(action, &writes)?;
    }
    KeyboardCommandKind::Reset => {
        for offset in &field.glyph_id_offsets {
            self.queue.write_buffer(&self.glyph_buffer, *offset,
                                    bytemuck::bytes_of(&0u32));
        }
        self.keyboard_cursors[slot] = 0;
    }
}
self.mark_dirty_tiles(command.tile_mask | self.sync_focus_visuals(),
                      "keyboard-command");
```

`form-row` 的三行 Settings 示例因此在 Rust 中表现为普通的三个 fields、三个 buttons、三组 action writes 和三个 tile masks，而不是一个新 widget 层。

## 4. System Settings showcase 的实际 lowering

`examples/settings-dashboard.rkt` 包含 `sample-interval-row`、`alert-threshold-row` 与 `batch-size-row` 三行。导出的 Scene 不包含 `tag: "form-row"` 或 `tag: "settings-form"`。其 command ABI 如下。

| slot | lowered field ID | Enter action | Enter/escape tile mask |
|---:|---|---|---|
| 0 | `sample-interval-row$field` | `apply-sample-interval` | `0x1` |
| 1 | `alert-threshold-row$field` | `apply-alert-threshold` | `0x2` |
| 2 | `batch-size-row$field` | `apply-batch-size` | `0x4` |

每个 Enter action 在这个 showcase 中更新同一行的 dynamic text state，因此 action tile 与 field tile 相同。这并不意味着 runtime 做了“行匹配”；它只是 compiler 已将 action 的 glyph write offsets 和 field layout 映射到同一个静态 tile。

## 5. 验证结果

| 验证层 | 命令 / oracle | 结果 |
|---|---|---|
| Racket 全量 regression | `PLTCOLLECTS="$PWD:" racket tests/run.rkt`，`FAILURE=0` | 通过 |
| Rust host | `cargo build --release --bin noir_winit_host` | 通过 |
| 原有 command showcase | `tools/verify_keyboard_command.sh` | 通过 |
| Settings showcase | `tools/verify_settings_form.sh` | 通过 |

Settings X11 oracle 使用真实 `xdotool` 键盘事件：`7 → Enter → Tab → 9 → Enter → Tab → 4 → Escape`。它验证两次 action dispatch 的固定 3-cell glyph patch、两次 compiler-defined focus transition，以及最后一行 Escape 对 `[2336, 2368, 2400]` 的 field-local zero-fill。日志位于 `wgpu-verify/out/settings-dashboard-e2e.log`。

## 6. 修改文件

| 文件 | 内容 |
|---|---|
| `noir/ui/main.rkt` | `parse-form-row`、`parse-settings-form`、parser dispatch、focus tile fallback |
| `examples/settings-dashboard.rkt` | 三行 System Settings showcase |
| `tests/run.rkt` | macro disappearance、focus ring、command table、button event oracle |
| `tools/verify_settings_form.sh` | Xvfb/X11/wgpu 端到端验证 |
| `wgpu-verify/src/bin/noir_winit_host.rs` | **无需 form-specific 改动**；复用通用 Command Map/Action/Tile ABI |

## References

实现与实验可在仓库内复现：`noir/ui/main.rkt`、`examples/settings-dashboard.rkt`、`tests/run.rkt`、`tools/verify_settings_form.sh`、`wgpu-verify/src/bin/noir_winit_host.rs` 与 `wgpu-verify/out/settings-dashboard-e2e.log`。
