# Noir Placement Renderer：GlyphPlacementInstance 与 Packet 驱动 wgpu 文本管线

**作者：Manus AI**  
**实现范围：** Rust 1.75、wgpu 0.20、winit 0.29.15（X11-only）、Racket `#lang noir/ui` Scene 编译器。  
**目标：** 让 wgpu 宿主真实消费 compiler 输出的 `glyph_placement_plan` 与 `glyph_draw_packets`，以固定 GPU instance ABI 与 packet draw 替换旧 text-run shader 中的运行时 glyph run 布局推导。

> 本阶段的结果是：静态 glyph 的位置、尺寸、UV、atlas page、clip/z/batch 归属都由编译器提前给出；动态数字仅覆写三个预留 glyph cell 的首个 `u32 glyph_id`。运行时不再根据 `glyph_count` 做除法，不再根据 `vertex_index / 6` 推导 run 内 glyph 序号，也不再由 host 遍历 QuadInstance 来发现文本。

## 1. 运行时路径变化

旧路径把一个 text-run 表示为一个 `QuadInstance`。WGSL 需要在顶点阶段根据 run rect、`glyph_count` 与 `vertex_index` 计算 glyph index、glyph x/y 和 glyph width；host 则遍历每个 render range 内的 QuadInstance，并在 `glyph_enabled` 时绘制 `glyph_count × 6` 顶点。

新路径把 compiler `Glyph Placement Plan` 上传为 GPU instance buffer。每个 glyph 是一个固定 instance，Draw Packet 直接给出连续的 instance range。动态文本仍以 glyph storage 保存内容，但只读取单个已编译 word offset；静态 glyph 不读取 glyph storage。

| 项目 | 旧 text-run 路径 | 新 Placement Renderer |
|---|---|---|
| 文本实例 | 每个 run 一个 44-byte `QuadInstance` | 每个 glyph 一个 48-byte `GlyphPlacementInstance` |
| glyph 几何 | shader 从 run rect 与 `glyph_count` 推导 | compiler 直接提供 NDC `pos` / `size` |
| Atlas UV | shader 由 glyph ID 与硬编码 cell 公式推导 | 静态 glyph 直接提供 compiler UV；动态 glyph 只计算新的 cell origin |
| 文本 draw | host 扫描 render range 内 QuadInstance | host 直接遍历 compiler `glyph_draw_packets` |
| 静态 glyph storage 读取 | 每个 glyph 均读取 | **零读取**；只用 placement 常量 |
| 动态数字更新 | 整段 3×32-byte cell payload，即 96 bytes | 三次固定 `u32` 写入，即 **12 bytes** |

## 2. Scene JSON 与 Rust 解码

Racket 编译器新增的 JSON 顶层字段被 Rust `Scene` 解码：

```rust
struct Scene {
    state: HashMap<String, i64>,
    resource_budget: ResourceBudget,
    layout_plan: Vec<LayoutEntry>,
    #[serde(default)] glyph_placement_plan: Vec<GlyphPlacementEntry>,
    #[serde(default)] glyph_draw_packets: Vec<GlyphDrawPacketEntry>,
    event_map: Vec<EventBinding>,
    actions: HashMap<String, ActionPlan>,
    render_schedules: Vec<RenderSchedule>,
}
```

`GlyphPlacementEntry` 对应 compiler 每个 glyph 的完整信息：slot、glyph ID、page、cell byte/word offset、NDC quad、UV、advance、动态标志、clip/z/batch。`GlyphDrawPacketEntry` 提供 page、连续 placement range、固定 glyph byte range 与组合信息。host 在构建 GPU buffer 前验证以下事实。

| 校验 | host 强制条件 |
|---|---|
| Placement 连续性 | `entry.slot == enumerate index` |
| cell ABI | `glyph_byte_offset == slot × 32`，`glyph_word_offset == glyph_byte_offset / 4` |
| page 编码 | `glyph_id >> 16 == atlas_page` |
| 字体度量 | `advance > 0` |
| Packet 连续覆盖 | packet `first_placement` 必须等于前一 packet 结尾 |
| Packet 对齐 | `glyph_byte_length == placement_count × 32` |
| Packet 一致性 | packet 内全部 placement 的 page 与 dynamic 属性一致 |

因此 JSON 不是“提示信息”：不满足 compiler ABI 的 Scene 会在 host 初始化阶段失败，而非进入不确定的渲染路径。

## 3. 48-byte `GlyphPlacementInstance` ABI

Rust 中的 placement vertex instance 采用 48-byte 的 `#[repr(C)]` 结构。它的布局与 wgpu vertex attributes 一一对应。

```rust
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GlyphPlacementInstance {
    pos: [f32; 2],              // byte 0..8，compiler NDC quad origin
    size: [f32; 2],             // byte 8..16，compiler NDC quad extent
    atlas_uv: [f32; 4],         // byte 16..32，静态 glyph 的 [u, v, du, dv]
    glyph_word_offset: u32,     // byte 32..36，动态 glyph 的 storage word 地址
    atlas_page: u32,            // byte 36..40，compiler atlas layer
    dynamic: u32,               // byte 40..44，0=static，1=仅内容动态
    _padding: u32,              // byte 44..48，保持 16-byte 尾对齐
}
```

| shader location | 字段 | 格式 | 偏移 |
|---:|---|---|---:|
| 1 | `pos` | `Float32x2` | 0 |
| 2 | `size` | `Float32x2` | 8 |
| 3 | `atlas_uv` | `Float32x4` | 16 |
| 4 | `glyph_word_offset` | `Uint32` | 32 |
| 5 | `atlas_page` | `Uint32` | 36 |
| 6 | `dynamic` | `Uint32` | 40 |

`placement_instances` 将 JSON 转成这个 ABI。静态 glyph 的 `glyph_word_offset` 替换为 `u32::MAX` sentinel；shader 的静态分支绝不读取该地址。动态 glyph 保持 compiler 给出的 word offset，例如 FPS 三个 slot 分别是 200、208、216，对应 buffer byte offsets 800、832、864。

## 4. 编译器 Placement Buffer 创建

宿主只在 Scene 初始化时构造一次 placement buffer：

```rust
let placements = placement_instances(&scene)?;
let placement_buffer = device.create_buffer_init(
    &wgpu::util::BufferInitDescriptor {
        label: Some("noir-compiler-glyph-placement-buffer"),
        contents: bytemuck::cast_slice(&placements),
        usage: wgpu::BufferUsages::VERTEX,
    },
);
```

Dashboard 编译产物有 31 个 placements，创建的 vertex buffer 为 `31 × 48 = 1488 bytes`。这是静态几何资源；交互 action 不会写它。

## 5. Packet 驱动渲染

新文本 pipeline 的 vertex state 是 `unit_layout()` 加 `glyph_placement_layout()`：每个 glyph 以一份 6 顶点单位 quad 和一个 placement instance 渲染。host 直接使用 compiler 的 packet range：

```rust
fn draw_glyph_packets(&self, pass: &mut wgpu::RenderPass<'_>) {
    pass.set_pipeline(&self.text_pipeline);
    pass.set_vertex_buffer(0, self.unit_quad.slice(..));
    pass.set_vertex_buffer(1, self.placement_buffer.slice(..));
    pass.set_bind_group(0, &self.glyph_bind_group, &[]);

    for packet in &self.scene.glyph_draw_packets {
        pass.draw(0..6,
                  packet.first_placement
                  ..packet.first_placement + packet.placement_count);
    }
}
```

Dashboard 的两个 packet 为：

| Packet | Atlas page | Instance range | glyph storage range | 动态性 |
|---|---:|---:|---:|---|
| `glyph-packet-page1-slot0-24` | 1 | `0..25` | `[0,800)` | 静态 title |
| `glyph-packet-page0-slot25-30` | 0 | `25..31` | `[800,992)` | FPS 与 latency 的预留 glyph slots |

当前示例的 packet clip stack 都是 `root`；当前 render schedule 已在每个 tile 设置 scissor。compiler 仍把 `clip_rect`、z layer 和 batch key 放入 packet ABI，后续可将不同 clip stack 的 packet 显式拆分为多次 scissor/batch draw，而无需重新分析 UI tree。

## 6. `host_placement.wgsl`

新文件 `wgpu-verify/src/host_placement.wgsl` 完全删除了旧 shader 的 run-layout 逻辑。它没有 `glyph_count` 输入，没有 `vertex_index / 6`，没有 `size.x / glyph_count`，也没有 run 内 glyph x/y 推导。

```wgsl
@vertex
fn vs_main(
  @location(0) corner: vec2<f32>,
  @location(1) pos: vec2<f32>,
  @location(2) size: vec2<f32>,
  @location(3) compiler_atlas_uv: vec4<f32>,
  @location(4) glyph_word_offset: u32,
  @location(5) compiler_atlas_page: u32,
  @location(6) dynamic: u32,
) -> VsOut {
  var atlas_uv = compiler_atlas_uv;
  var atlas_page = compiler_atlas_page;

  if (dynamic != 0u) {
    let glyph_id = glyph_words[glyph_word_offset];
    let glyph_index = glyph_id & 0xffffu;
    atlas_page = glyph_id >> 16u;
    atlas_uv = vec4<f32>(
      (f32(glyph_index) * 6.0 + 1.0) / 162.0,
      1.0 / 8.0,
      3.0 / 162.0,
      5.0 / 8.0,
    );
  }

  out.position = vec4<f32>(pos + corner * size, 0.0, 1.0);
  out.uv = atlas_uv.xy + corner * atlas_uv.zw;
  out.atlas_page = i32(atlas_page);
}
```

静态分支仅执行 compiler constants 到 shader outputs 的拷贝与一次 atlas array sample。动态分支只读取一个 `u32 glyph_id`，将其变成 page-0 cell origin；NDC geometry、UV 宽高、packet 与 draw range 均不改变。

## 7. 12-byte 动态 glyph ID 更新

Racket 的 `gpu-update` 扩展为 `glyph-id-offsets`。对 FPS：

```text
glyph_id_offsets = [800, 832, 864]
```

对 latency：

```text
glyph_id_offsets = [896, 928, 960]
```

compiler 的 `frame_schedule` 也同步将原本每 action 一个 `[offset, 96]` 写集改成三个 `[offset, 4]` 写集。Rust action dispatch 只格式化固定数量数字，随后对每个 offset 做一次 `queue.write_buffer`：

```rust
for (offset, glyph_id) in offsets.iter().zip(glyph_ids.iter()) {
    self.queue.write_buffer(&self.glyph_buffer,
                            *offset as u64,
                            &glyph_id.to_le_bytes());
}
```

host 还检查每个离散 offset 都位于 compiler 声明的总 glyph range 内，并确认 offset 数量与 glyph slot 数相同。这使 12-byte 更新既是性能优化，也是保持 fixed-write proof 的 ABI 检查。

| Action | 旧写入 | 新写入 | 节省 |
|---|---:|---:|---:|
| `refresh-fps` | 一个 96-byte payload | 三个 4-byte `glyph_id` | 84 bytes，87.5% |
| `refresh-latency` | 一个 96-byte payload | 三个 4-byte `glyph_id` | 84 bytes，87.5% |
| `advance-progress` | 一个 4-byte `size.x` | 不变 | 已是字段级最小写入 |

## 8. 验证证据

| 验证层 | 执行内容 | 结果 |
|---|---|---|
| Racket compiler oracle | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 通过；确认 31 placements、2 packets、三个 4-byte FPS/latency 写集 |
| Rust release build | `cargo build --release --bin noir_winit_host` | 通过；无 warning |
| wgpu pipeline | 真实 Vulkan/llvmpipe、`D2Array` atlas、Placement Buffer 和 `host_placement.wgsl` | 成功创建并绘制 |
| 真实 X11 输入 | Xvfb 中以 `xdotool` 点击三枚 Event Map 按钮 | 通过 |
| glyph write oracle | 检查日志的全部离散 range | FPS、latency 各为 12 bytes，且准确落在预编译 cell 首字 |
| geometry patch oracle | progress 点击 | 仍只写 `[316,320)` 的 4-byte `size.x` |

最终真实运行日志为：

```text
compiler glyph placement resources: 31 placement instance(s), 2 page-aware packet(s), ABI=48 bytes
noir-winit-host: 15 quad instances, 31 glyph placement(s), 2 packet(s), profile=noir-vulkan-gpu-matrix-v1
glyph-id-patch fps: [800..804), [832..836), [864..868) (12 bytes)
glyph-id-patch latency: [896..900), [928..932), [960..964) (12 bytes)
instance-patch progress: [316..320)
winit host Placement Buffer + packet renderer + 12-byte glyph-ID patch roundtrip verified.
```

Xvfb 的 DRI3 警告反映其没有直通硬件 DRI3；验证仍实际运行 wgpu Vulkan/llvmpipe、Surface present、WGSL pipeline 和 X11 事件循环，不是 mock 或纯 CPU 单测。

## 9. 可复现步骤

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" racket tests/run.rkt

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/placement-renderer.scene.json

cd wgpu-verify
cargo build --release --bin noir_winit_host
cd ..
./tools/verify_winit_host.sh out/placement-renderer.scene.json
```

## 10. 关键实现文件

| 文件 | 本阶段角色 |
|---|---|
| `noir/ui/main.rkt` | 输出 `glyph_id_offsets`，并把 action/frame schedule lowering 为三个固定 4-byte 写集 |
| `wgpu-verify/src/bin/noir_winit_host.rs` | 解码/验证 Placement JSON、创建 48-byte instance buffer、packet draw、离散 ID patch |
| `wgpu-verify/src/host_placement.wgsl` | 直接渲染 compiler NDC/UV；动态分支只读取一个 `u32` |
| `tools/verify_winit_host.sh` | 断言 31 placements、2 packets、两组 12-byte 更新与 progress 4-byte patch |
| `tests/run.rkt` | compiler-level placement/packet/离散写集 oracle |

> 结论：Noir 的 Glyph Placement Plan 已经进入真实 wgpu 渲染关键路径。静态文本的 layout 工作被完全编译掉；动态数字不再覆写 96-byte glyph payload，而是以三个预先证明不重叠的 4-byte glyph ID 写入驱动同一 Placement Renderer。
