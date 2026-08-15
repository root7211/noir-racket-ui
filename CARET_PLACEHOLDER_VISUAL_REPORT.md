# Noir 编译期 Caret、Placeholder 与 Focus Visual

**作者：Manus AI**  
**状态：Racket compiler、Rust/wgpu host 与真实 X11 验证通过**

## 摘要

本阶段让已具备 Focus Graph 与固定容量数字编辑能力的 `text-field` 获得可见的焦点、占位文本和 blink caret。实现延续 Noir 的编译型原则：field rect、caret x positions、placeholder glyph packet、focus/caret instance offsets、blink period、tile IDs 都在 macro expansion 后确定；运行时没有字体测量、node lookup、layout 计算或通用 animation scheduler。

> 每次 focus、digit、Backspace 或 blink phase 只写 compiler 指定的 `QuadInstance` field；glyph buffer 与 visual instance buffer 均有固定、可审计的 byte address。

## Text-field 内联

一个 field：

```racket
(text-field #:id query-field
            #:state query-value
            #:max-chars 3
            #:tab-index 20
            #:charset digits
            #:placeholder "INPUT"
            #:width 240)
```

在编译期 hygienically 内联为既有原语子树：

| 派生 ID | 基础原语 | 初始 alpha | 职责 |
|---|---|---:|---|
| `query-field$field-shell` | `stack` | 1.0 | 固定 clip/geometry shell |
| `query-field$focus` | `overlay` | 0.0 | focus visual，激活后 alpha 0.30 |
| `query-field$placeholder` | static `text` | 0.45 | page-1 shaped placeholder glyph packet |
| `query-field` | dynamic `text-run` | 1.0 | 固定 3 slot digits glyph buffer |
| `query-field$caret` | `overlay` | 0.0 | 2 px caret，z=41 |

这些都是原有 parser 的 `stack`、`overlay`、`text` child；不存在 runtime component 或 visual object。field 本体仍保留调用者提供的 ID，因而 Focus Graph 和 Keyboard Map ABI 不变。

## Visual Plan ABI

Scene JSON 新增 `text_field_visuals`。对每个 focus slot，它提供：

```json
{
  "focus_slot": 0,
  "node": "command-field",
  "tile_ids": [1],
  "max_chars": 3,
  "focus_instance_offset": 352,
  "focus_alpha_offset": 380,
  "placeholder_instance_offset": 396,
  "placeholder_alpha_offset": 424,
  "caret_instance_offset": 484,
  "caret_pos_x_offset": 484,
  "caret_alpha_offset": 512,
  "caret_ndc_x_positions": [-0.88125, -0.63125, -0.38125, -0.13125],
  "blink_track": {
    "id": "command-field-caret-blink",
    "period_ms": 500,
    "alpha": [1.0, 0.0]
  }
}
```

`QuadInstance` 的 `pos.x` 位于 instance offset，color alpha 位于 `instance_offset+28`。因此 digit 输入从 cursor 0 到 cursor 1 后，caret update 不需要对 glyph advance 求和：直接从 `caret_ndc_x_positions[1]` 取 `-0.63125` 并写入固定 `[caret_pos_x_offset..+4)`。

## 编译期与启动期不变量

Racket 检查每个 visual child 都能从 Focus Graph field ID 推导，且 field glyph count 决定 caret table 的 `max_chars+1` 行数。回归 oracle 固化了两个 field 的 visual instance offsets、NDC table、blink period 和 focus tile ownership。

Rust 在启动期验证 visual field 数与 Focus Graph 相等，node/max chars 与 Keyboard Map 相等，tile mask 与 Focus Graph 相等，caret position table 具有 `max_chars+1` 元素，blink period 非零，并检查所有 instance byte offsets 位于资源预算内、按 4-byte 对齐且满足 QuadInstance 的 `pos.x` / alpha ABI。运行时只保留按 focus slot 排列的 `CompiledTextFieldVisual` 数组。

## 运行时路径

焦点、键盘与 blink 都调用同一 `sync_focus_visuals`：

```rust
patch_instance_f32(visual.focus_alpha_offset, focused ? 0.30 : 0.0);
patch_instance_f32(visual.placeholder_alpha_offset, cursor == 0 ? 0.45 : 0.0);
patch_instance_f32(visual.caret_pos_x_offset, visual.caret_ndc_x_positions[cursor]);
patch_instance_f32(visual.caret_alpha_offset, focused && blink_on ? 1.0 : 0.0);
```

blink 使用单一 host monotonic clock；compiler 固定 period 为 500 ms。host 没有每-field timer；当相位变化时只标记当前 focus field 的 compiler tile mask。

## 真实验证证据

`tools/verify_visual_text_field.sh` 在 Xvfb、X11 `xdotool`、Vulkan/llvmpipe 和真实 wgpu Surface 上执行 digit 7、Tab、digit 4、Backspace。日志验证：

```text
text-field-visual sync: slot=0 cursor=0 caret_ndc_x=-0.88125
  focus_alpha=0.30 placeholder_alpha=0.45 mask=0x2

keyboard-transition insert: command-field digit-7
  glyph-id-patch [896..900), cursor 0->1
text-field-visual sync: slot=0 cursor=1 caret_ndc_x=-0.63125
  placeholder_alpha=0

focus-tab forward: slot 0 -> 1 / query-field
text-field-visual sync: slot=1 cursor=0 caret_ndc_x=-0.88125
  focus_alpha=0.30 placeholder_alpha=0.45 mask=0x1

keyboard-transition backspace: query-field
  glyph-id-patch [640..644), cursor 1->0
text-field-visual sync: slot=1 cursor=0 caret_ndc_x=-0.88125
  placeholder_alpha=0.45
```

Visual placeholder contributes page-1 static packets, while dynamic field digits remain page-0 placements. Query tile 0 submits page-1 placeholder range `[15..20)` and page-0 dynamic range `[20..23)`; no full text rerender or shaping occurs.

## 边界

focus visual 当前是半透明 field overlay，而不是四边描边 geometry；它仍由同一 static quad renderer 画出。Backspace 仍是 zero-fill，field visual 根据 cursor（不是 glyph content）恢复 placeholder。没有 selection、left/right cursor movement、IME 或 variable-width shaping。它们必须继续通过 fixed visual instances、cursor position tables 和 compiler transition map 扩展，不能回到 runtime string/layout 系统。

## 复现命令

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host && cd ..
./tools/verify_visual_text_field.sh
```
