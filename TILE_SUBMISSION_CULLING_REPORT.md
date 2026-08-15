# Noir Tile-Aware Submission Culling：Rust `glyph_packet_ranges` 消费路径

**作者：Manus AI**  
**实现范围：** Rust 1.75、wgpu 0.20、winit 0.29.15 X11-only 宿主；输入为 Racket `#lang noir/ui` 已编译的 Packet-Aware Tile Culling Scene。  
**目标：** 使 wgpu 宿主不再在每个 scissor tile 中提交所有 glyph draw packet，而是只执行 compiler `render_tile.glyph_packet_ranges` 给出的 placement subrange。

> 本阶段已经把 compiler 的 tile culling plan 接入真实 GPU draw submission。宿主不再做 packet/tile 相交、glyph/tile 相交、UI tree 扫描或 layout 搜索；其 tile 文本路径只执行编译器已经选定的 instance range。当前 host 在任一 canvas dirty 时仍遍历 schedule 的全部 tile，这是“按 action 选择 tile”的下一阶段工作；但每个 tile 已不会提交其 `glyph_packet_ranges` 以外的文本。

## 1. 运行时路径变化

此前 Placement Renderer 已以 compiler placement buffer 渲染文本，但 `draw_glyph_packets` 对每个 tile 遍历所有 `glyph_draw_packets`。scissor 能丢弃 tile 外 fragment，却仍提交了 tile 外 glyph 的 vertex instances。

新路径分为全量和局部两个明确 API。初始全量 canvas 绘制调用 `draw_all_glyph_packets`，而 `redraw_canvas_tiles` 对每个 compiler scissor tile 调用 `draw_tile_glyph_packets`。后者的唯一 glyph draw 输入是对应 tile 的 `glyph_packet_ranges`。

| 路径 | 旧行为 | 新行为 |
|---|---|---|
| 初始 full redraw | 绘制全部 packet | 保持全部 packet，确保完整 canvas 初始内容 |
| 局部 tile redraw | 每 tile 绘制 page-1 title packet 与 page-0 dynamic packet | 每 tile 仅绘制 compiler subrange；title packet 没有任何局部 tile range |
| FPS/latency metrics tile | 每 tile 最多 31 glyph instances | 分别仅为 3 glyph instances |
| progress/button tile | 即使没有文本也可进入全部 packet loop | `glyph_packet_ranges=[]`，零文本 draw |

## 2. Rust Scene ABI

`GlyphDrawPacketEntry` 解码 compiler 新增的 `bounds`；`ScissorTile` 解码 `glyph_packet_ranges`；每个 subrange 保留 packet stable index、placement interval、bounds 和 dynamic 属性。

```rust
#[derive(Debug, Deserialize)]
struct ScissorTile {
    x: f32, y: f32, width: f32, height: f32,
    draw_ranges: Vec<DrawRange>,
    glyph_packet_ranges: Vec<GlyphPacketRange>,
}

#[derive(Debug, Deserialize)]
struct GlyphPacketRange {
    packet_id: String,
    packet_index: usize,
    first_placement: u32,
    placement_count: u32,
    bounds: [f32; 4],
    dynamic: bool,
}
```

这里的 `packet_index` 是 Racket packet table 的稳定数组下标。draw loop 不使用 `packet_id` 做查表；ID 只用于启动期 ABI 防线和日志可审计性。

## 3. 启动期 ABI 验证

`validate_tile_glyph_ranges` 在创建 GPU Placement Buffer 前运行。它不重新计算 culling，而是检查 compiler 输出的计划满足可安全执行的前提。

| 验证 | 条件 |
|---|---|
| packet 地址有效 | `packet_index < glyph_draw_packets.len()` |
| index/ID 一致 | range 的 `packet_id == packets[packet_index].id` |
| placement ownership | subrange 完全属于 packet 的 `[first_placement, first+placement_count)` |
| 非空 draw | `placement_count > 0` |
| dynamic 一致 | range 与 packet 的 `dynamic` 相同 |
| bounds 合法 | packet bounds 和 range bounds 都与 tile 相交 |
| range 顺序 | 同一 tile 中同一 packet 的多个 subrange 不重叠且按 instance address 单调 |

核心代码如下。

```rust
fn validate_tile_glyph_ranges(scene: &Scene) -> Result<(usize, u32)> {
    let mut range_count = 0usize;
    let mut instance_count = 0u32;

    for (tile_index, tile) in scene.render_schedules.iter()
        .flat_map(|schedule| schedule.tiles.iter())
        .enumerate()
    {
        let tile_bounds = [tile.x, tile.y, tile.width, tile.height];
        let mut prior_end_by_packet: HashMap<usize, u32> = HashMap::new();

        for range in &tile.glyph_packet_ranges {
            anyhow::ensure!(range.packet_index < scene.glyph_draw_packets.len(),
                "tile {tile_index} references an invalid packet");
            let packet = &scene.glyph_draw_packets[range.packet_index];
            anyhow::ensure!(range.packet_id == packet.id,
                "tile packet ID disagrees with packet index");

            let packet_end = packet.first_placement + packet.placement_count;
            let range_end = range.first_placement + range.placement_count;
            anyhow::ensure!(range.placement_count > 0
                && range.first_placement >= packet.first_placement
                && range_end <= packet_end,
                "tile range escapes packet placement interval");
            anyhow::ensure!(range.dynamic == packet.dynamic,
                "dynamic flag disagrees with packet");
            anyhow::ensure!(rects_intersect(packet.bounds, tile_bounds)
                && rects_intersect(range.bounds, tile_bounds),
                "compiler range does not intersect its tile");

            if let Some(prior_end) = prior_end_by_packet.insert(range.packet_index, range_end) {
                anyhow::ensure!(prior_end <= range.first_placement,
                    "subranges are overlapping or non-monotonic");
            }
            range_count += 1;
            instance_count += range.placement_count;
        }
    }
    Ok((range_count, instance_count))
}
```

Dashboard 启动日志确认 compiler plan 有 **5 个 scissor tile、2 个 submitted subrange、总计 6 个局部 glyph instances**。

## 4. Placement pipeline 绑定与全量路径

全量和局部路径复用同一 pipeline/buffer bind 函数，避免在 tile path 中创建或重新解释 GPU 资源。

```rust
fn bind_glyph_placement_pipeline(&self, pass: &mut wgpu::RenderPass<'_>) {
    pass.set_pipeline(&self.text_pipeline);
    pass.set_vertex_buffer(0, self.unit_quad.slice(..));
    pass.set_vertex_buffer(1, self.placement_buffer.slice(..));
    pass.set_bind_group(0, &self.glyph_bind_group, &[]);
}

fn draw_all_glyph_packets(&self, pass: &mut wgpu::RenderPass<'_>) {
    self.bind_glyph_placement_pipeline(pass);
    for packet in &self.scene.glyph_draw_packets {
        pass.draw(0..6,
                  packet.first_placement
                  ..packet.first_placement + packet.placement_count);
    }
}
```

`redraw_canvas_full` 调用 `draw_all_glyph_packets`，保证 full canvas 初始绘制仍包含静态 page-1 title 和所有 dynamic glyph slots。

## 5. `draw_tile_glyph_packets`

局部路径不遍历 `glyph_draw_packets`，也不使用 packet bounds 进行动态筛选。它读取当前 tile 的已经验证的 range list，并直接把 `first_placement..end` 作为 vertex instance range 传给 wgpu。

```rust
fn draw_tile_glyph_packets(
    &self,
    pass: &mut wgpu::RenderPass<'_>,
    tile_index: usize,
    ranges: &[GlyphPacketRange],
) {
    if ranges.is_empty() { return; }

    self.bind_glyph_placement_pipeline(pass);
    for range in ranges {
        let packet = &self.scene.glyph_draw_packets[range.packet_index];
        let end = range.first_placement + range.placement_count;
        println!(
            "tile-glyph-draw tile={tile_index} packet={} page={} \
             placements=[{}..{}) count={} dynamic={}",
            range.packet_index, packet.atlas_page,
            range.first_placement, end,
            range.placement_count, range.dynamic,
        );
        pass.draw(0..6, range.first_placement..end);
    }
}
```

这里 `packet` 只用于 page-aware diagnostic；实际 draw 不需要读取 page、bounds、node、layout 或 glyph IDs。WGSL 仍使用相同的 `GlyphPlacementInstance`，静态/动态 glyph 的区别也仍由 placement `dynamic` flag 决定。

## 6. Tile redraw loop 改造

`redraw_canvas_tiles` 在每个 compiler scissor tile 中先清 tile，再渲染 quad draw ranges，最后调用该 tile 的 glyph range list。

```rust
for (tile_index, tile) in schedule.tiles.iter().enumerate() {
    pass.set_scissor_rect(
        tile.x.max(0.0) as u32,
        tile.y.max(0.0) as u32,
        tile.width.max(1.0) as u32,
        tile.height.max(1.0) as u32,
    );

    pass.set_pipeline(&self.static_pipeline);
    pass.set_vertex_buffer(0, self.unit_quad.slice(..));
    pass.set_vertex_buffer(1, self.clear_buffer.slice(..));
    pass.draw(0..6, 0..1);

    self.draw_ranges(&mut pass, tile.draw_ranges.iter());
    self.draw_tile_glyph_packets(
        &mut pass, tile_index, &tile.glyph_packet_ranges,
    );
}
```

普通 `draw_ranges` 已被缩减为 QuadInstance 绘制函数，不再隐式调用任意文本 draw。这个分离是避免未来有人在 static draw path 中意外恢复“全 packet per tile”提交的结构性边界。

## 7. Dashboard 的实际 submission

Racket compiler 输出的五个 tile 中，只有两个 metrics tile 有 glyph ranges。真实运行的每次 tile canvas redraw 均记录：

```text
compiler tile glyph culling: 5 scissor tile(s), 2 submitted subrange(s), 6 glyph instance(s)
tile-glyph-draw tile=0 packet=1 page=0 placements=[25..28) count=3 dynamic=true
tile-glyph-draw tile=1 packet=1 page=0 placements=[28..31) count=3 dynamic=true
```

| Tile | Compiler subrange | 实际 wgpu draw instance count | 静态 page-1 title packet |
|---:|---|---:|---|
| 0，FPS metrics | packet 1, `25..28` | 3 | 不提交 |
| 1，latency metrics | packet 1, `28..31` | 3 | 不提交 |
| 2，progress | 空 | 0 | 不提交 |
| 3，按钮 1 | 空 | 0 | 不提交 |
| 4，按钮 3 | 空 | 0 | 不提交 |

验证脚本明确拒绝包含 `packet=0` 的 `tile-glyph-draw` 日志，并拒绝 tile `2`、`3`、`4` 的任何 glyph draw。因此它证明当前局部 tile submission path 不会重新提交静态 title 的 25 glyph，也不会在无文本的 tile 中提交 dynamic glyph。

## 8. 真实验证

| 验证层 | 执行内容 | 结果 |
|---|---|---|
| Rust build | `cargo build --release --bin noir_winit_host` | 通过，无 warning |
| Scene ABI | 启动时验证 packet index/ID、placement ownership、dynamic 与 bounds | 通过 |
| GPU | Vulkan/llvmpipe 下创建 wgpu Surface、D2Array Atlas、Placement Buffer 与 WGSL pipeline | 通过 |
| 输入 | Xvfb + `xdotool` 点击 FPS、latency 和 progress 三个 Event Map hit rect | 通过 |
| 文本写入 | FPS/latency 分别 3 次 4-byte glyph-ID 写入，共 12 bytes | 通过 |
| Submission oracle | 仅 logs `tile=0/1, packet=1, count=3`，无 packet 0、无 tiles 2–4 glyph draw | 通过 |

完整复现：

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/tile-culling.scene.json

cd wgpu-verify
cargo build --release --bin noir_winit_host
cd ..
./tools/verify_winit_host.sh out/tile-culling.scene.json
```

## 9. 当前边界与下一阶段

本次已消除“每个 tile 提交全部 text packet”的问题，但 dirty canvas 仍重绘 Scene schedule 的全部五个 tile。因此刷新 FPS 时，host 会执行 tile 0 和 tile 1 的两个 3-instance draw；它不再提交 25 glyph 的 title，也不向无文本 tile 提交 glyph。

真正将 FPS action 缩至 **单 tile / 单 packet / 3 instances** 的下一阶段是 **Action-Aware Tile Selection**：Racket 为每个 action、hover、pressed、release task 输出 tile ID list；host 根据事件只执行被该 task 标注的 tile。该阶段不会改变本次的 glyph range ABI，而只是将已验证的 tile plan 加入 action dispatch 选择器。

> 结论：Noir 已从“scissor 丢弃 tile 外 fragment”推进到“编译器只让宿主提交 tile 内 glyph placement instance”。文本 geometry、packet membership、instance range 和局部 GPU 写入范围均由编译产物决定。
