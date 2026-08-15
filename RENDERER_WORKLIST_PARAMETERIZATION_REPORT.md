# Renderer Worklist Parameterization 完成报告

**项目：** Noir Racket UI / wgpu host  
**范围：** 将延迟重绘路径中的 `dirty_tiles`、`pending_strategy` 与 `pending_packet_worklist` 合并为显式 `RenderRequest` 队列。  
**状态：** 已实现并通过 Racket、Rust release、真实 X11 鼠标和真实 X11 表单回归。

## 1. 重构目标

此前，事件处理器先把 tile mask 写入 `Host.dirty_tiles`，再把 packet worklist 写入 `Host.pending_packet_worklist`，某些 compiler-selected 路径还会写入 `Host.pending_strategy`。`RedrawRequested` 随后从这些彼此独立的可变字段中拼装渲染输入。这使正确性依赖于写入顺序，并允许不同事件的 tile mask 与 worklist slot 在延迟呈现边界发生错误配对。

本次重构将 renderer 的完整调度输入定义为单一数据对象：

```rust
#[derive(Clone, Copy, Debug)]
struct RenderRequest {
    tile_mask: u64,
    strategy: Option<CompilerStrategy>,
    packet_worklist_index: usize,
}
```

其三个字段均为编译器 artifact 的运行时索引或直接投影。事件期不会构造 packet range、重新计算 tile geometry，或根据文本内容推断 GPU 写入范围。

| 字段 | 来源 | 事件期允许的操作 |
|---|---|---|
| `tile_mask` | compiler action、frame-task、transaction 或 transient task 的固定 tile 表 | 位或合并相同请求 |
| `strategy` | compiler choice/proof，或 `None` 的常规局部更新 | 仅分派已验证的 executor |
| `packet_worklist_index` | all/dynamic/no-packets、field-local、transaction-local 或 batch task slot | 传给 packet activity compute dispatch |

## 2. Rust 宿主重构

### 2.1 消除三项分离的延迟渲染状态

`Host` 已删除以下兼容字段：

```rust
pending_packet_worklist: usize
pending_strategy: Option<CompilerStrategy>
dirty_tiles: u64
```

替代字段为：

```rust
pending_render: Vec<RenderRequest>
```

`enqueue_render` 接受一个完整 request。它只会合并**相邻且 strategy 与 packet worklist slot 都相同**的请求；不同 slot 的 request 保持队列顺序。这是必要的不变量：即使 tile mask 可安全相并，混合两个 local worklist 仍会扩大 compute prepass 的 packet activity 写入范围，违反 compiler-lowered GPU 写范围契约。

```rust
if let Some(last) = self.pending_render.last_mut() {
    if last.strategy == request.strategy
        && last.packet_worklist_index == request.packet_worklist_index {
        last.tile_mask |= request.tile_mask;
        return;
    }
}
self.pending_render.push(request);
```

`mark_dirty_tiles` 保留为 transient visual 路径的小包装，但它直接调用 `RenderRequest::no_packets(mask)`；因此 hover、pressed、release、focus 和 caret blink 也不再隐式依赖 Host worklist 状态。

### 2.2 Renderer 接口成为显式数据流

`redraw_selected_tiles` 已从 mask 参数改为：

```rust
fn redraw_selected_tiles(
    &mut self,
    request: RenderRequest,
    measure_gpu: bool,
    cpu_started: Option<Instant>,
) -> (SubmittedTileStats, Option<f64>, Option<u128>)
```

compute prepass 直接使用 `request.packet_worklist_index`：

```rust
self.encode_packet_activity(&mut encoder, request.packet_worklist_index);
```

原先的：

```rust
std::mem::replace(&mut self.pending_packet_worklist, 2)
```

已完全删除。`present` 现在通过 `redraw_canvas_requests` 取走 `pending_render` FIFO，并对每个 request 显式执行 coalesced、packet-aware 或 full-redraw 路径。Full replay 固定采用 `RenderRequest::ALL_PACKETS`，符合编译器全包重放契约。

## 3. 已迁移的生产路径

| 触发路径 | RenderRequest worklist | strategy |
|---|---:|---|
| ASCII/digit keyboard transition | `keyboard_packet_worklist_indices[slot]` | `None` |
| command matcher 命中或拒绝 | 当前 field-local slot | `None` |
| Enter 的普通 Action write | `no-packets`（2） | `None` |
| Enter commit-pending-register / Escape reset | 当前 field-local slot | `None` |
| Enter commit-group / pointer transaction | `transaction_packet_worklist_indices[index]` | `None` |
| hover、pressed、release、focus、caret blink | `no-packets`（2） | `None` |
| coalesced batch replay | `CompiledBatch.task_worklist_indices` 中最后一个非 `no-packets` slot，或 2 | `None` |
| compiler-selected Coalesced | batch-selected slot | `Some(Coalesced)` |
| compiler-selected PacketAware | batch-selected slot | `Some(PacketAware)` |
| compiler-selected FullRedraw | `all-packets`（0） | `Some(FullRedraw)` |
| replay matrix ActionAware | `no-packets`（2） | `None` |
| replay matrix PacketAware | `all-packets`（0） | `None` |

其中 batch executor 的返回类型已由 `Option<CompiledBatch>` 改为 `Option<(CompiledBatch, usize)>`。这使 worklist slot 与 batch mutation result 一起离开执行器，而非被写入 Host 的侧通道字段。

## 4. X11 Oracle 更新

`tools/verify_winit_host.sh` 已升级为 RenderRequest oracle。它不再检查旧的 `tile-select` 文本，而是验证：

1. hover request 显式以 `worklist=2` 入队；
2. pressed/release coalesced transient batch 输出 `worklist_slots=[2, 2]`；
3. 三个 activate batch 输出 compiler-fixed slot，并以 `strategy=Some(Coalesced)` 入队；
4. `no-packets` slot 导致 packet activity compute 正确输出 `compiler-empty` skip；
5. 源码中不存在 `pending_packet_worklist`、`pending_strategy` 或 `dirty_tiles` 字段。

`tools/verify_settings_form.sh` 同步升级为验证 field-local 和 transaction-local request：field 0 使用 slot 3；field 1 使用 slot 4；field 2 使用 slot 5；`apply-all` transaction 使用 slot 6。

> 注意：历史 `registry-match.rkt` 源文件不在当前项目树中，而旧的 `out/registry-match.scene.json` 不满足新增 subgroup coverage proof。因此，回归 scene 由当前 `examples/dashboard.rkt` 重新导出到同一路径；其语义正是原鼠标 Action/Transient dashboard oracle 所覆盖的三按钮工作负载。

## 5. 验证记录

| 验证项 | 命令或方式 | 结果 |
|---|---|---|
| Racket compiler 全量回归 | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 通过 |
| Rust 静态类型检查 | `cargo check --bin noir_winit_host` | 通过；仅既有非阻塞 warning |
| Rust release 构建 | `cargo build --release --bin noir_winit_host` | 通过；仅既有非阻塞 warning |
| RenderRequest static contract | grep 旧字段与 renderer 调用签名 | 通过 |
| 鼠标 coalesced X11/Vulkan | `tools/verify_winit_host.sh` | 通过 |
| Settings Form X11/Vulkan | `tools/verify_settings_form.sh` | 通过 |

真实鼠标回归的实际日志包含下列关键证据：

```text
render-request-enqueue hover: ... worklist=2
packet-activity-skip worklist=no-packets index=2 packets=[] reason=compiler-empty
coalesced-batch execute: coalesced-activate-refresh-fps-button ... worklist_slots=[2, 2]
render-request-enqueue coalesced-activate-refresh-fps-button: ... strategy=Some(Coalesced) worklist=2
```

真实 Settings Form 回归同时确认：

```text
render-request-enqueue keyboard-transition: ... worklist=3
packet-activity-dispatch worklist=field-sample-interval-row$field index=3 packets=[3]
render-request-enqueue keyboard-command: ... worklist=6
packet-activity-dispatch worklist=transaction-apply-all index=6 packets=[3, 6, 9]
```

## 6. 结果与后续扩展边界

现在，任务到 GPU 的路径为：

```text
X11/winit input
  → compiler-fixed task / action / transaction / batch ref
  → state and GPU write plan
  → RenderRequest { tile_mask, strategy, packet_worklist_index }
  → FIFO queue preserving worklist boundaries
  → wgpu packet activity compute + indirect draw / selected tile renderer
```

该路径不再通过单独的 Host worklist side channel 传播 GPU packet 范围。下一步如需支持一次输入触发多个不同 field-local worklist，应保留本次引入的 FIFO 语义：生产多个 `RenderRequest`，而不是把它们压缩为一个扩大范围的 union worklist。这样可以延续 Noir 的核心约束，即 compiler 既决定屏幕局部区域，也决定 GPU 可写 packet 的最小范围。
