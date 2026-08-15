# Noir 编译期 Focus Graph 与 Tab 焦点切换

**作者：Manus AI**  
**状态：已通过 Racket、Rust/wgpu 与真实 X11 验证**

## 摘要

本阶段将 Noir 从纯鼠标交互的编译型 dashboard 推进到具有**编译期键盘导航**的 GUI 框架。`#lang noir/ui` 新增受限 `text-field` form；它不在运行时构造 field object，而是展开为既有的固定容量动态 `text` / `text-run` 原语，并附加只在编译器中使用的 `focusable` 与 `tab-index` metadata。

编译器在 Layout Plan、Render Schedule 和 Tile Culling 已固定后构造 `focus_graph`。其中每个 entry 都有稳定 slot、field ID、state ID、tab index、next/previous slot、预编译 tile IDs 和 instance offset。Rust host 在启动期验证该表，压缩 tile IDs 为固定 `u64` mask；收到 Tab 或 Shift+Tab 时只读取当前 slot 的 `next_slot` 或 `previous_slot`，更新一个小整数状态并提交 compiler 指定的 tile。

> 本阶段实现的是**焦点导航**，不是通用文本编辑器。它没有字符串 allocation、IME、Unicode shaping、cursor 或 selection runtime；这些功能必须以同样的固定容量 ABI 在后续阶段加入。

## DSL 表面语法

`text-field` 接受的全部决定参数均为宏展开期 literal：

```racket
(text-field #:id query-field
            #:state query-value
            #:max-chars 3
            #:tab-index 20
            #:width 240)
```

其 lowering 等价于以下基础 text primitive，并只额外保存 compiler-private metadata：

```racket
(text #:id query-field
      #:width 240
      #:dynamic query-value
      #:max-chars 3)
```

因此既有 Glyph Atlas、Glyph Placement Plan、固定 glyph ID offset、Packet-Aware Tile Culling 和 Action-Aware Tile Selection 都无需复制实现。text field 的 `#:tab-index` 必须是非负精确整数；多个 field 的 tab index 相同会在宏展开期失败。

| 输入约束 | 编译期含义 | 运行时后果 |
|---|---|---|
| `#:id` | stable node/layout/glyph identity | 无 field lookup |
| `#:state` | 固定动态 glyph backing state | 已知 glyph cell range |
| `#:max-chars` | 固定 32-byte glyph cell 容量 | 无扩容、无 reflow |
| `#:tab-index` | Focus Graph 唯一排序键 | 无排序或 tree traversal |
| `#:width` / `#:height` | 固定 Layout Plan rect | 无 focus-time geometry 计算 |

## Focus Graph ABI

Racket runtime Scene 新增以下纯数据结构：

```racket
(struct focus-entry
  (slot node state tab-index next-slot previous-slot tile-ids instance-offset)
  #:transparent)
(struct focus-graph (entries initial-slot) #:transparent)
```

Scene JSON 的 `focus_graph` 是后端输入，而不是描述性 metadata。典型 output 如下：

```json
{
  "focus_graph": {
    "entries": [
      {
        "slot": 0,
        "node": "command-field",
        "state": "command-value",
        "tab_index": 5,
        "next_slot": 1,
        "previous_slot": 1,
        "tile_ids": [1],
        "instance_offset": 132
      },
      {
        "slot": 1,
        "node": "query-field",
        "state": "query-value",
        "tab_index": 20,
        "next_slot": 0,
        "previous_slot": 0,
        "tile_ids": [0],
        "instance_offset": 88
      }
    ],
    "initial_slot": 0
  }
}
```

示例的 tree order 是 `query-field` 再 `command-field`，但 Focus Graph 明确按 `tab_index=5,20` 排序。这证明 surface/tree order 没有泄漏为 runtime 决策。

## 编译器算法与不变量

`compile-focus-graph` 执行以下工作。

| 步骤 | 编译器操作 | 禁止留给 runtime 的工作 |
|---|---|---|
| 收集 | 仅选择 compiler 标记为 `focusable` 的 lowered text nodes | UI tree scan |
| 排序 | 按静态 `tab-index` 升序排序 | Tab 时排序/搜索 |
| 验证 | 拒绝重复 tab index | 模糊 focus precedence |
| 环路 | 为 slot `i` 生成 `(i+1) mod n` 与 `(i-1+n) mod n` | 分支式 wraparound 计算 |
| Tile 选择 | 将 field Layout Plan rect 与已编译 render tiles 相交 | runtime rect/tile intersection |
| 证明 | 验证 slot 密集、tile IDs 升序/去重、transition 落在表内 | host 恢复或推断 graph |

Focus Graph 依赖已完成的 layout 和 render schedules，因此 field 的 tile IDs 是先前 Tile Culling 语义的一部分，而非单独的 focus renderer。

## Rust 宿主：启动期验证与事件期最短路径

Rust 的 `compiler_focus_graph` 在窗口创建时验证：

1. 空 graph 仅能使用 `initial_slot=-1`；非空 graph 的 initial slot 必须在 entry table 内。
2. entry slot 必须为 `0..n-1` 稠密序列，tab index 必须严格递增。
3. next/previous 必须是 compiler 的 canonical ring transition。
4. state、Layout Plan node、instance offset 和 glyph slots 必须一致。
5. entry tile IDs 复用既有 `tile_mask` validator，因而仍要求非空、升序、无重复、在 64-bit tile table 内。

成功后 host 只保留：

```rust
struct CompiledFocusEntry {
    node: String,
    next_slot: usize,
    previous_slot: usize,
    tile_mask: u64,
}
```

Tab event 的关键路径为：

```rust
let target = if reverse {
    graph.entries[from].previous_slot
} else {
    graph.entries[from].next_slot
};
graph.current_slot = target;
self.mark_dirty_tiles(graph.entries[target].tile_mask, "focus-tab");
```

Host 不读取 `tab_index`，不查询 layout，不遍历 text fields，不计算 damage rect，也不读取 profile 或 strategy costs。`WindowEvent::KeyboardInput` 只匹配 `NamedKey::Tab`；`ModifiersChanged` 记录固定 Shift modifier state 来选择 previous transition。

## 示例与验证

`examples/focus-dashboard.rkt` 包含两个 fields：`command-field` 的 tab index 是 5，而较早出现的 `query-field` 的 tab index 是 20。它们由两个普通 action plans 提供固定 text damage tiles，保证 focus transition 可进入实际 tile renderer。

| 验证层 | 结果 |
|---|---|
| Racket parser | `text-field` 仅降低为动态 `text-run`，没有 runtime text-field tag |
| Focus Graph oracle | 固定 slots `[0,1]`、nodes `[command-field, query-field]`、next `[1,0]`、previous `[1,0]`、tiles `[(1),(0)]` |
| Rust release build | `cargo build --release --bin noir_winit_host` 通过 |
| 真实 GPU backend | Vulkan/llvmpipe 的 wgpu Surface 成功创建并渲染 |
| 真实键盘输入 | Xvfb 下通过 X11 `windowfocus` + `xdotool key Tab` / `shift+Tab` 注入 |

真实日志给出完整的运行时路径：

```text
focus-tab forward: slot 0 -> 1 / query-field mask=0x0000000000000001
tile-select focus-tab: mask=0x0000000000000001
tile-submit tile=0
tile-glyph-draw tile=0 packet=1 page=0 placements=[15..18) count=3 dynamic=true

focus-tab reverse: slot 1 -> 0 / command-field mask=0x0000000000000002
tile-select focus-tab: mask=0x0000000000000002
tile-submit tile=1
tile-glyph-draw tile=1 packet=1 page=0 placements=[18..21) count=3 dynamic=true
```

这表明 Tab / Shift+Tab 进入真实 winit X11 event loop 后，分别只提交了被 compiler 选择的一个 tile 和对应三字形 placement range。

## 运行命令

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

# Racket 全量回归（含 Focus Graph oracle）
PLTCOLLECTS="$PWD:" racket tests/run.rkt

# Rust release host
cd wgpu-verify
cargo build --release --bin noir_winit_host
cd ..

# 真实 X11 Tab / Shift+Tab 闭环
./tools/verify_focus_graph.sh
```

## 当前边界与后续工作

Focus Graph 已把**导航顺序、transition、field geometry ownership 和 tile submission**固定下来。后续的固定容量 ASCII text editing 可以在同一 graph 上增加 `Keyboard Map`：每个 field 为允许字符、Backspace、Enter 输出已知的 glyph ID cell offsets 与 caret instance offset。届时运行时仍只做 key→预编译 transition→固定 buffer writes，而不是引入通用字符串系统。
