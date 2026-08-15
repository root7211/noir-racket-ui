# 固定容量 Uppercase ASCII Text Register

**作者：Manus AI**

## 目标与边界

本阶段为 `#lang noir/ui` 的 `text-field` 增加了受限 `#:charset ascii-upper`。该模式仅接受 **A–Z、空格与 Backspace**，容量固定为 1–8 个字符。它不引入运行时字符串、UTF-8 解码、字形 shaping、哈希表分派或动态 glyph atlas 查询。

> 文本并非作为动态字符串管理；它是一个由 compiler 预先定位的有限状态寄存器：`focus slot + cursor + packed u64 + fixed glyph cell offsets`。

| 项目 | digits | ascii-upper |
|---|---:|---:|
| Register | `u32` 十进制累计值 | 最多 8 byte 的 packed `u64` |
| 键表 | `digit-0..9` + Backspace，共 11 条 | `letter-A..Z` + Space + Backspace，共 28 条 |
| Atlas page | 0 | 1 |
| 插入语义 | `v' = v × 10 + d` | `packed' = packed \| (byte << cursor×8)` |
| 删除语义 | `v' = v / 10` | 清除 `(cursor-1)×8` 处的 byte |
| 空 cell glyph | page-0 digit `0` | page-1 space `0x00010000` |

## Racket 宏与编译期 lowering

`text-field` parser 现接受 `#:charset digits`（默认）与 `#:charset ascii-upper`。后者在 macro expansion 期拒绝大于 8 的 `#:max-chars`，随后仍完全内联为既有 `stack / text / overlay` 基础节点，不产生新的 runtime widget 类型。

```racket
(text-field #:id command-entry
            #:state command-buffer
            #:max-chars 6
            #:tab-index 0
            #:charset ascii-upper
            #:on-enter commit
            #:on-escape reset)
```

编译器为此 field 产生 `ascii-text-register`，包括 `charset`、`max_chars`、`initial_packed`、`reset_packed` 与固定 `atlas_page=1`。其 `Keyboard Map` 在宏展开期证明：A–Z 的 operands 连续为 ASCII `65..90`，Space operand 为 `32`，glyph IDs 分别为 page-1 的 `1..26` 与 `0`，Backspace 固定写 page-1 space。每条 transition 都共享该 field 已证明的 tile mask。

动态 glyph binding 也会预填 page-1 space glyph，而不是使用数字 page-0 的零字形。Glyph Placement 因而从启动时就处于正确 page/UV/batch packet，运行时只写首个 `glyph_id` word。

## Rust 宿主执行结构

Rust `KeyboardField` 现在解码 `charset`、可选 `digit_register` 与可选 `ascii_text_register`。启动期 admission 对 `ascii-upper` 验证：descriptor 完整、`atlas_page=1`、无 digit descriptor、每个 glyph offset 对齐且严格递增，以及全部 28 条 transition 的 key/kind/cursor/glyph/register metadata 精确匹配。

宿主为每个 focus slot 保留两类定长 pending storage：`keyboard_pending_values: Vec<u32>` 服务 digits，`keyboard_text_values: Vec<u64>` 服务 ASCII。它们均由 compiler descriptor 初始化，不包含 `String` 或文本容器。

```rust
let shift = (cursor * 8) as u32;
let next = packed | (u64::from(transition.register_operand) << shift);
queue.write_buffer(&glyph_buffer, glyph_offset, bytes_of(&transition.glyph_id));
keyboard_cursors[slot] = cursor + 1;
keyboard_text_values[slot] = next;
```

Backspace 以固定掩码清除一个 byte，并将对应 cell 复位为 page-1 space glyph。Enter 沿用 compiler-selected `commit-pending-register`：对 ASCII field，它将 packed `u64` 直接转换为审计用 `i64` 并写入已证明的 `state_index`。Escape 只清空本 field 的固定 glyph offsets、cursor 和 packed pending register。

## Command Palette 与真实验证

`examples/command-palette.rkt` 提供了 6-cell `ascii-upper` field。`tools/verify_ascii_text_register.sh` 使用真实 Xvfb、winit、wgpu 与 xdotool 输入：

```text
G → P → U → Space → Backspace → Enter → Escape
```

| Oracle | 观察结果 |
|---|---|
| Compiler admission | `chars=6`、`atlas_page=1`、`transitions=28` |
| A–Z patches | `G=71`、`P=80`、`U=85` 写入固定 glyph offsets |
| Space 与 deletion | Space 写 page-1 glyph `65536`；Backspace 恢复同一 cell 为 page-1 space |
| Enter commit | `GPU` 的 little-endian packed value `0x00555047 = 5591111` 写入 `command-buffer` State Slot 0 |
| Escape reset | `0x0000000000555047 → 0x0000000000000000`，且仅清空 command field slots |
| GPU scheduling | 每个编辑/command 仅提交 compiler-selected tile 0 与既有 packet subrange |

验证矩阵已通过：Racket 全量 regression 为 **0 个 FAILURE**；Rust `cargo build --release --bin noir_winit_host` 通过；新的 ASCII X11/wgpu oracle 通过；既有 digits Command Map X11/wgpu oracle 也通过，确认两种 charset 的 ABI 可共存。

## 仍然受限的部分

当前文本 State Slot 使用 packed `u64`，因此适用于最多 8 个 uppercase ASCII bytes 的固定命令、标签或过滤 token。它不是 Unicode 字符串系统，也不支持编辑中间插入、选择区、变宽 glyph、换行或任意字形 fallback。这是刻意的性能边界；下一阶段若扩展字符集，应继续保持 fixed alphabet、fixed capacity、fixed glyph cells 与 compiler-generated transition table。

## 可复现命令

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd .. && tools/verify_ascii_text_register.sh
tools/verify_keyboard_command.sh
```
