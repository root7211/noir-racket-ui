# Noir Rust Action-Aware Tile Renderer：消费编译期 `tile_ids`

**作者：Manus AI**  
**实现范围：** Rust 1.75、wgpu 0.20、winit 0.29.15（X11-only）宿主；消费 `#lang noir/ui` 编译器输出的 action/frame-task `tile_ids` 与既有 `glyph_packet_ranges`。  
**目标：** 使 runtime event dispatch 不再把 canvas 标为“全 schedule dirty”，而是只 OR compiler 已计算的 tile 地址；渲染循环只提交被该固定 mask 选中的 scissor tiles。

> compiler 负责决定“哪些 tile”；host 负责执行“这些 tile”。在 event fast path 中没有 damage rect、node traversal、bounds test、tile search、`HashSet` 或排序。唯一的调度合并操作是预验证 `u64` mask 的按位 OR。

## 1. 端到端路径

此前 `Action-Aware Tile Selection` 已将 action 和 frame task 的 `tile_ids` 写入 Scene JSON，但是 wgpu host 对任意交互仍遍历完整六 tile schedule。现在 host 启动时验证并压缩所有 ID 列表；hover、pressed、release、action 再把对应 mask OR 进 `dirty_tiles`。`present()` 只调用 draw loop 遍历这个 mask 中的 bit。

| 事件阶段 | compiler 输入 | host 操作 | 实际提交 |
|---|---|---|---|
| FPS hover | `hover-refresh-fps-button → [3]` | OR `1 << 3` | tile 3，零 glyph |
| FPS pressed | `pressed-refresh-fps-button → [3]` | OR `1 << 3` | tile 3，零 glyph |
| FPS release + action | `release → [3]`、`refresh-fps → [0]` | OR `0x8 | 0x1 = 0x9` | tile 0 的 3 glyph + tile 3 的按钮回弹 |
| latency release + action | `[4] + [1]` | OR `0x10 | 0x2 = 0x12` | tile 1 的 3 glyph + tile 4 |
| progress release + action | `[5] + [2]` | OR `0x20 | 0x4 = 0x24` | tile 2 + tile 5，均零 glyph |

release 与 action 同帧保留两个 tile 是必要的视觉正确性：按钮的 pressed position/color 必须恢复，同时 action 的 metrics/progress 内容必须更新。它们被固定 word 合并，不存在运行时的 rect union。

## 2. Rust Scene ABI

Scene 解码增加 action `tile_ids` 和 frame task table。

```rust
#[derive(Clone, Debug, Deserialize)]
struct ActionPlan {
    #[serde(default)] writes: Vec<StateWrite>,
    #[serde(default)] gpu_updates: Vec<GpuUpdate>,
    #[serde(default)] instance_updates: Vec<InstanceUpdate>,
    #[serde(default)] tile_ids: Vec<usize>,
}

#[derive(Debug, Deserialize)]
struct FrameTask {
    id: String,
    kind: String,
    #[serde(default)] tile_ids: Vec<usize>,
}
```

事件 table 在启动期降为三个 mask：

```rust
#[derive(Clone, Copy)]
struct EventTileMasks {
    hover: u64,
    pressed: u64,
    release: u64,
}
```

`Host` 只持有 action mask map、每 Event Map slot 的 transient masks 和 `dirty_tiles: u64`。六 tile dashboard 因而只使用低六位，但 ABI 明确限制一个受限 Noir profile 最多 64 tile；超限是启动期错误，而非隐式退化。

## 3. 启动期验证与固定 mask lowering

`tile_mask` 将 compiler list 压缩为 word，并拒绝所有可能破坏最短路径的 Scene：空列表、越界 ID、重复 ID、非升序 ID 和超过 64 tile 的 schedule。

```rust
fn tile_mask(tile_ids: &[usize], tile_count: usize, owner: &str) -> Result<u64> {
    anyhow::ensure!(tile_count <= 64, "{owner}: tile count exceeds u64 mask");
    anyhow::ensure!(!tile_ids.is_empty(), "{owner}: empty tile_ids plan");

    let mut mask = 0u64;
    let mut previous = None;
    for &tile_id in tile_ids {
        anyhow::ensure!(tile_id < tile_count, "{owner}: invalid tile ID");
        if let Some(prior) = previous {
            anyhow::ensure!(prior < tile_id,
                "{owner}: tile IDs must be strictly ascending and unique");
        }
        mask |= 1u64 << tile_id;
        previous = Some(tile_id);
    }
    Ok(mask)
}
```

`compiler_tile_selection` 随后构造 `HashMap<String, u64>` 的 action table，并按 `event_map` 顺序构造无查找的 `Vec<EventTileMasks>`。task name、kind 与 compiler Event Map 的绑定在启动时验证；事件期不再通过字符串拼接或 task table 查找 task。

启动诊断为：

```text
compiler action tile selection: 3 action mask(s), 3 event transient mask(s), fixed-mask=u64
```

## 4. 事件分发

所有事件入口都调用同一个小函数：

```rust
fn mark_dirty_tiles(&mut self, mask: u64, source: &str) {
    if mask == 0 { return; }
    self.dirty_tiles |= mask;
    self.canvas_dirty = true;
    println!("tile-select {source}: mask=0x{:016x}", mask);
}
```

`set_hover` 仅 patch 两个已知 color field，并合并 old/new event 的 precompiled hover masks。`pointer_down` 仅 patch已知 pressed pos/color fields 并选择 pressed mask。`pointer_up` 先恢复 base fields、选择 release mask；如果 hit test 仍命中同一 slot，再执行 action 的固定 GPU writes 和 action mask。

```rust
fn pointer_up(&mut self) {
    if let Some(index) = self.pressed.take() {
        let action = self.scene.event_map[index].action.clone();
        self.patch_color(index, self.scene.event_map[index].base_color);
        self.patch_pos(index, self.scene.event_map[index].base_pos);
        self.mark_dirty_tiles(self.event_tile_masks[index].release, "release");
        if self.hit_test(self.cursor) == Some(index) {
            self.dispatch_action(&action);
        }
    }
}
```

`dispatch_action` 保留既有的三次 4-byte glyph ID patch 或一次 4-byte progress size patch；所有写入完成后，它只读取启动期已验证的 action mask 并调用 `mark_dirty_tiles`。

## 5. 仅选中 tile 的 wgpu draw loop

`redraw_canvas_tiles` 对 `dirty_tiles` 执行 `mem::take`。这同时清空本帧 work list，且避免以 heap allocation 转移运行时状态。随后它在稳定 schedule 数组上按 index 顺序扫描并只在对应 bit 为 1 时提交 tile。

```rust
fn redraw_canvas_tiles(&mut self) {
    let selected_mask = std::mem::take(&mut self.dirty_tiles);
    if selected_mask == 0 {
        self.canvas_dirty = false;
        return;
    }

    let schedule = self.scene.render_schedules.first().unwrap();
    println!("tile-redraw selected-mask=0x{selected_mask:016x}");
    // begin wgpu render pass ...
    for (tile_index, tile) in schedule.tiles.iter().enumerate() {
        if selected_mask & (1u64 << tile_index) == 0 {
            continue;
        }
        println!("tile-submit tile={tile_index}");
        pass.set_scissor_rect(/* compiler tile rect */);
        self.draw_ranges(&mut pass, tile.draw_ranges.iter());
        self.draw_tile_glyph_packets(
            &mut pass, tile_index, &tile.glyph_packet_ranges,
        );
    }
    // submit encoder
    self.canvas_dirty = false;
}
```

这段循环不重算 tile bounds、glyph bounds、packet membership 或 text layout。`glyph_packet_ranges` 继续确保 tile 0/1 各只提交 3 dynamic glyph placements；tile 2–5 的 range 均为空。

## 6. 真实 X11 提交证据

`verify_winit_host.sh` 在 Xvfb、Vulkan/llvmpipe、真实 wgpu Surface 和 `xdotool` 点击下验证 action mask、transient mask、placement submission 与 GPU write range。

| 操作 | 核心日志 | 证明 |
|---|---|---|
| FPS action | `tile-select refresh-fps: mask=...0001` | action 只引用 tile 0 |
| FPS release+action | `tile-redraw selected-mask=...0009` | tile 3 release 与 tile 0 action 做常量 OR |
| FPS glyph draw | `tile-glyph-draw tile=0 ... placements=[25..28) count=3` | 仅 metrics subrange 提交 |
| latency release+action | `selected-mask=...0012` | tile 4 与 tile 1 |
| latency glyph draw | `tile=1 ... placements=[28..31) count=3` | 仅 latency subrange 提交 |
| progress release+action | `selected-mask=...0024` | tile 5 与 tile 2，二者无 glyph draw |
| 静态 title | 没有 `tile-glyph-draw ... packet=0` | page-1 25 glyph 未参与局部提交 |

FPS 的 content-update 仍严格为：

```text
glyph-id-patch fps: [800..804), [832..836), [864..868) (12 bytes)
```

latency 同样为 12 bytes；progress 仍仅写 `[316..320)` 的 4 bytes。Tile selection 不改变任何 compiler 已证明的 GPU write ABI。

## 7. 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/action-tile-selection.scene.json

cd wgpu-verify
cargo build --release --bin noir_winit_host
cd ..
./tools/verify_winit_host.sh out/action-tile-selection.scene.json
```

## 8. 结论与下一阶段

Noir 的 action path 已闭环为：

> **Event Map slot → compiler frame-task/action tile ID → fixed `u64` OR → selected scissor tile → compiler packet range → fixed Placement Buffer instance range。**

对于 FPS 业务更新，必要的内容 tile 只有 tile 0 和 glyph range `25..28`；同帧 tile 3 的存在仅用于 release button 的正确视觉恢复。下一步适合实现 **Frame-Task Coalescing + priority winner execution**：让同一浏览器/窗口事件批次的多个 compiler task 按已存在的 conflict graph priority 合并 field writes、tile masks 与 draw submissions，并用 timestamp 报告量化从完整 schedule 到单 tile 的 CPU/GPU 工作差异。
