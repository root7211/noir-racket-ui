# Noir Rust Coalesced Batch Executor：执行 compiler `frame_coalesced_batches`

**作者：Manus AI**  
**实现范围：** Rust 1.75、wgpu 0.20、winit 0.29.15（X11-only）的 `noir_winit_host`。  
**输入契约：** Racket `#lang noir/ui` 在宏展开期生成的 `frame_coalesced_batches`、`frame_schedule`、`event_map`、`glyph_packet_ranges` 与 Action-Aware `tile_ids`。  
**目标：** 让 host 不再在 pointer down/up 分别调用 pressed、release、action 的通用路径；而是按 compiler batch 执行 winner-only byte writes，并一次性用 premerged tile mask 触发局部 render pass。

> Racket compiler 已证明哪一个 task 赢得每一段重叠字节写入。Rust host 的职责不是重新排序或重新裁决，而是验证 proof、执行 winner segment、使用 compiler 合并的 tile 地址。

## 1. Runtime ABI

Scene 解码增加 batch 结构：

```rust
#[derive(Clone, Debug, Deserialize)]
struct FrameCoalescedWrite {
    task_id: String,
    offset: usize,
    byte_length: usize,
}

#[derive(Clone, Debug, Deserialize)]
struct FrameCoalescedElimination {
    task_id: String,
    offset: usize,
    byte_length: usize,
    winner: String,
}

#[derive(Clone, Debug, Deserialize)]
struct FrameCoalescedBatch {
    id: String,
    task_ids: Vec<String>,
    execution_order: Vec<String>,
    winner_writes: Vec<FrameCoalescedWrite>,
    eliminated_writes: Vec<FrameCoalescedElimination>,
    merged_tile_ids: Vec<usize>,
    conflict_edges: Vec<BatchConflictEdge>,
}
```

启动期将 JSON batch 降为一个 `CompiledBatch`：固定 execution order、固定 winner write array 和固定 `u64` tile mask。每个 Event Map slot 也预绑定到 `coalesced-press-<node>` 与 `coalesced-activate-<node>`，并建立 `frame task ID → event slot` 的固定 map。后续 pointer path 不做 Scene tree 遍历、task 排序、range overlap 或 tile ID union。

| Host 数据 | 建立时机 | 事件期用途 |
|---|---|---|
| `coalesced_batches` | Scene 初始化 | batch ID → winner writes + tile mask |
| `event_batch_ids` | Scene 初始化 | Event Map slot → press/activate batch ID |
| `frame_task_event_slots` | Scene 初始化 | transient task ID → fixed event slot |
| `dirty_tiles` | 每个 frame | 一次 `u64` OR，随后 selected-tile draw |

## 2. 启动期 proof validation

Host 不盲信 JSON。`compiler_coalesced_batches` 在创建 wgpu resource 前验证：

| 验证项 | Rust 条件 |
|---|---|
| task member | 每个 batch task ID 必须出现在 `frame_schedule` |
| execution order | 必须等于 `(priority ascending, task ID ascending)` 的稳定排序 |
| tile plan | `merged_tile_ids` 非空、升序、无重复、位于 render tile 表内，并压缩至 64-bit mask |
| winner ownership | 每一个 winner write 必须完全落在 source task 的 raw write range 内 |
| elimination ownership | loser 与 winner 必须共同拥有该 byte segment，且 Rust 重算 priority winner 必须等于 compiler winner |
| conflict edge | left/right 必须属于 batch；winner 与每个 overlap 都必须成立 |
| event mapping | 每个 Event Map node 必须拥有 hover/pressed/release task 及 press/activate batch 对 |

例如 priority winner 在 host 中使用与 compiler 一致的规则：

```rust
fn task_winner_id(left: &FrameTask, right: &FrameTask) -> String {
    if left.priority > right.priority { left.id.clone() }
    else if left.priority < right.priority { right.id.clone() }
    else if left.id < right.id { left.id.clone() }
    else { right.id.clone() }
}
```

任何 ABI 违例会使 `Host::new` 返回错误；不存在“回退到 generic scheduler”的静默路径。

启动日志为：

```text
compiler frame coalescing: 6 verified batch(es), 3 event batch pair(s)
```

## 3. Winner-only transient patch

`apply_transient_winner_write` 接收 compiler write `(task_id, offset, byte_length)`，由预绑定 task ID 取得 event slot，再严格接受两种合法 field：button pos `[instance_offset, +8)` 和 color `[instance_offset+16, +32)`。

```rust
if offset == pos_offset && byte_length == 8 {
    self.instances[pos_offset / 44].pos = pos;
    self.queue.write_buffer(&self.instance_buffer, offset as u64,
                            bytemuck::cast_slice(&pos));
} else if offset == color_offset && byte_length == 16 {
    self.instances[event.instance_offset / 44].color = color;
    self.queue.write_buffer(&self.instance_buffer, offset as u64,
                            bytemuck::cast_slice(&color));
} else {
    anyhow::bail!("winner write does not match its fixed visual field")
}
```

因此 malformed batch 无法借 transient executor 改写任意 instance field。pressed/release/hover 的颜色与 position 也来自 Event Map 的 compiler-fixed values，非运行时样式计算。

## 4. Action winner patch

`apply_action_winner_writes` 先应用固定 state write，再对 compiler action 的每个 glyph ID offset 检查 batch 是否具有一个同 ID、同 offset、长度为 4 的 winner record。只有 winner segment 被写入：

```rust
if writes.iter().any(|write| {
    write.task_id == action_id && write.offset == *offset && write.byte_length == 4
}) {
    self.queue.write_buffer(&self.glyph_buffer, *offset as u64,
                            &glyph_id.to_le_bytes());
}
```

若 compiler batch 漏掉必须的 glyph/instance field，executor 立即失败，不会进行部分 action update。现有 dashboard 因而维持：

| Action | winner-only GPU write |
|---|---:|
| `refresh-fps` | `[800,804)`、`[832,836)`、`[864,868)`，共 12 bytes |
| `refresh-latency` | `[896,900)`、`[928,932)`、`[960,964)`，共 12 bytes |
| `advance-progress` | `size.x [316,320)`，共 4 bytes |

## 5. Batch executor 与渲染

Pointer down 直接选择 `coalesced-press-*`；命中 pointer up 选择 `coalesced-activate-*`。executor clone 启动期验证后的 small batch，不访问通用 scheduler：

```rust
fn execute_coalesced_batch(&mut self, batch_id: &str) {
    let batch = self.coalesced_batches.get(batch_id).cloned().unwrap();
    for task_id in &batch.execution_order {
        let task_writes = batch.winner_writes.iter()
            .filter(|write| write.task_id == *task_id)
            .cloned().collect::<Vec<_>>();
        if self.scene.actions.contains_key(task_id) {
            self.apply_action_winner_writes(task_id, &task_writes)?;
        } else {
            for write in &task_writes {
                self.apply_transient_winner_write(task_id, write.offset,
                                                  write.byte_length)?;
            }
        }
    }
    self.mark_dirty_tiles(batch.tile_mask, &batch.id);
}
```

`batch.tile_mask` 已是 compiler `merged_tile_ids` 的启动期压缩结果，故 `redraw_canvas_tiles` 的现有 selected-bit draw loop 可以直接工作。它继续消费 compiler `glyph_packet_ranges`，因此 tile 0/1 各只提交相应的 3 glyph placement instance。

对于 pointer up 在 button 外部的取消点击，host 不使用 activate batch（因为 action 不可触发）；它执行 compiler `release-<node>` task 的固定 base pos/color，并使用 release tile mask。这是唯一保留的非 batch transient restoration path，且不会进入业务 action。

## 6. 真实 X11 验证证据

验证使用 Vulkan/llvmpipe、真实 wgpu Surface、Xvfb、winit X11 event loop 与 `xdotool` 三个点击。`verify_winit_host.sh` 现在断言 batch proof startup、winner-only writes、merged masks 和 packet draw。

| 输入 | 关键日志 | 实际结果 |
|---|---|---|
| FPS press | `coalesced-press-refresh-fps-button` | 只出现 pressed `[528,536)` 与 `[544,560)` winner writes；没有 `coalesced-winner transient hover-refresh-fps-button` |
| FPS activate | `coalesced-activate-refresh-fps-button` | release winner fields + 3 个 4-byte glyph writes；mask `0x9` |
| FPS text submit | `tile=0 ... placements=[25..28) count=3` | 只提交 page-0 FPS glyph subrange |
| latency activate | mask `0x12` | tile 1 + tile 4；glyph range `[28..31)` |
| progress activate | mask `0x24` | tile 2 + tile 5；4-byte instance patch，无 glyph draw |
| static title | 无 `packet=0` tile glyph log | page-1 的 25 静态 glyph 不参与局部重绘 |

真实日志同时确认 host 有 **6 verified batch** 和 **3 event batch pairs**。Release + action 的 tile mask 仍保留两个 tile 是视觉必要性：一个 tile 用于按钮回弹，另一个 tile 用于业务内容更新；它们的 union 完全由 compiler 固定，而非 runtime damage 合并。

## 7. 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/frame-coalescing.scene.json

cd wgpu-verify
cargo build --release --bin noir_winit_host
cd ..
./tools/verify_winit_host.sh out/frame-coalescing.scene.json
```

## 8. 结论与后续

Noir 的交互 fast path 已完成 compiler-to-host coalescing：

> **Event Map slot → compiler batch ID → verified winner writes → fixed GPU byte writes → premerged tile mask → compiler packet range → Placement Buffer instance draw。**

Frame coalescing 不会把 physically separate frames 的 hover 写入事后“撤销”；本实现只对同一 coalesced batch 的 task 写集删除 loser segment。X11 harness 中鼠标移动与按下之间存在单独呈现周期，因此 hover 可先真实呈现；pointer-down batch 自身仍只执行 pressed winner writes，且 log 证明它从未执行 hover winner write。

下一阶段适合实现 **timestamp query microbenchmark matrix**：用同一 dashboard 在 full schedule、tile culling、action-aware、coalesced executor 四条路径上测量 GPU pass 时间、draw instance 数、`queue.write_buffer` 次数和 CPU event-to-submit 时间，形成可发布的性能证据。 
