# Noir wgpu Timestamp Query 微基准矩阵

**作者：Manus AI**  
**实现范围：** Rust 1.75、wgpu 0.20、Vulkan/llvmpipe、winit X11-only host。  
**目标：** 以 compiler 已生成的 Coalesced Activate Batch 为固定微基准 case，在真实 wgpu canvas pass 上采集 GPU timestamp、CPU event-to-submit 时间，以及 compiler tile/placement/winner-write 预期的实际执行计数，并输出可审计 JSON。

> Noir 的性能主张不以泛化 UI benchmark 代替可追溯的路径证明。每一条 benchmark row 都绑定一个 compiler batch ID、其 winner-only write set、merged tile mask 和 packet placement range；若 host 的实际提交计数不符合 compiler 预期，基准立即失败，不生成“看似正常”的结果。

## 1. 基准 CLI 与报告

宿主新增 CLI：

```bash
noir_winit_host SCENE.json --benchmark-report REPORT.json
```

启动仍创建真实 X11 window、wgpu Surface 和 canvas renderer；但在资源初始化后直接执行固定 compiler batch matrix、写出 JSON 并退出，不依赖手工鼠标时序。

```json
{
  "schema": "noir-wgpu-benchmark-v1",
  "renderer": "coalesced-batch-executor + action-aware tile + placement renderer",
  "profile_id": "noir-vulkan-gpu-matrix-v1",
  "adapter_name": "...",
  "backend": "Vulkan",
  "timestamp_query_supported": true,
  "timestamp_period_ns": 1.0,
  "cases": []
}
```

每个 case 输出固定 execution order、expected/observed tile mask、winner write count/bytes、submitted tile count、glyph draw count、glyph instance count、CPU event-to-submit 纳秒数、GPU elapsed 纳秒数和 `expectations_match`。

| 字段 | 含义 | 取值来源 |
|---|---|---|
| `expected_winner_write_*` | batch 最短字段写集的大小 | compiler `winner_writes` |
| `expected_tile_mask_hex` | 合并后的 dirty tile 地址 | compiler `merged_tile_ids` 启动期转 `u64` |
| `submitted_*` | 实际 canvas pass 的 local work | Rust selected-tile loop 的真实计数 |
| `cpu_event_to_submit_ns` | batch executor 入口至 canvas `queue.submit` | `Instant`，readback 等待不计入 |
| `gpu_elapsed_ns` | canvas pass query 0–1 的 GPU tick 差 | timestamp resolve/readback × adapter period |
| `expectations_match` | compiler 与实际 selected submission 一致 | host 运行时强制断言 |

## 2. wgpu Feature 协商与 timestamp 实现

wgpu 0.20 的 command encoder `write_timestamp` 需要同时启用：

```rust
let timestamp_features = wgpu::Features::TIMESTAMP_QUERY
    | wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS;
let timestamp_supported = adapter.features().contains(timestamp_features);
let requested_features = if timestamp_supported {
    timestamp_features
} else {
    wgpu::Features::empty()
};
```

当 adapter 不支持这两个 feature 时，host 继续运行 benchmark matrix，但报告 `timestamp_query_supported=false` 且 GPU 字段为 `null`；不会因时间戳不可用而伪造数值。当前 Vulkan llvmpipe adapter 支持该 feature 对，因此报告的 `timestamp_period_ns` 为 1.0。

每轮 case 使用一个包含两个 timestamp slot 的 `QuerySet`，以及 16-byte resolve/readback buffers。

```rust
encoder.write_timestamp(&timer.query_set, 0);
// selected compiler tile canvas pass
encoder.write_timestamp(&timer.query_set, 1);
encoder.resolve_query_set(&timer.query_set, 0..2, &timer.resolve_buffer, 0);
encoder.copy_buffer_to_buffer(&timer.resolve_buffer, 0,
                              &timer.readback_buffer, 0, 16);
queue.submit(Some(encoder.finish()));
```

GPU completion 后，host map readback buffer、读取两个 `u64` tick，并按 `queue.get_timestamp_period()` 转换：

```rust
let elapsed_ns = (end_tick - start_tick) as f64
    * timer.timestamp_period_ns as f64;
```

CPU 指标在 `queue.submit` 立即之后截取；GPU map/readback 同步仅用于取得 timestamp，不会污染 `cpu_event_to_submit_ns`。

## 3. 真实基准 case

矩阵自动枚举并按字典序排序 compiler 所发射的 `coalesced-activate-*` batch。每个 case 在执行前清空 `dirty_tiles`；host 执行真实 Coalesced Batch Executor，再取实际 tile mask 调用 `redraw_selected_tiles(mask, true, Some(start))`。

| Case | compiler tile mask | winner writes | glyph submit |
|---|---:|---:|---:|
| `coalesced-activate-advance-progress-button` | `0x24` | 3 / 28 bytes | 0 draw / 0 instances |
| `coalesced-activate-refresh-fps-button` | `0x09` | 5 / 36 bytes | 1 draw / 3 instances |
| `coalesced-activate-refresh-latency-button` | `0x12` | 5 / 36 bytes | 1 draw / 3 instances |

progress 的 28 winner bytes 包括 release button pos 8 bytes、release color 16 bytes 和 progress `size.x` 4 bytes。FPS/latency 的 36 bytes 包括相同 24-byte release field set 加 3 个 4-byte dynamic glyph IDs。

在每次 canvas submit 后，host 独立从 `render_schedules[].tiles[]` 基于 batch mask 计算 expected tile/glyph stats，并与绘制 loop 实际计数逐项比较。任何不一致会抛出错误：

```rust
let expectations_match = observed_mask == batch.tile_mask
    && observed_stats.tile_count == expected_stats.tile_count
    && observed_stats.glyph_draw_count == expected_stats.glyph_draw_count
    && observed_stats.glyph_instance_count
        == expected_stats.glyph_instance_count;
anyhow::ensure!(expectations_match,
    "benchmark case diverged from compiler tile/placement contract");
```

## 4. 真实 Vulkan/llvmpipe 测量结果

本次验证运行在 `llvmpipe (LLVM 20.1.2, 256 bits)`、Vulkan backend、timestamp period 1.0 ns 的 Xvfb X11 surface 上。下表来自 `out/wgpu-benchmark.json` 的单次真实测量；数值用于路径可执行性和相对工作量审计，不应外推为物理 GPU 的绝对性能结论。

| Case | Tiles | Glyph draws / instances | CPU event→submit | GPU canvas elapsed | Contract |
|---|---:|---:|---:|---:|---|
| Progress activate | 2 | 0 / 0 | 14,552,065 ns | 473,722 ns | match |
| FPS activate | 2 | 1 / 3 | 171,105 ns | 487,105 ns | match |
| Latency activate | 2 | 1 / 3 | 97,123 ns | 334,343 ns | match |

首个 progress case 的 CPU 值明显大于后续 case，符合首次 GPU work/driver path 热身会混入首轮 CPU dispatch 的行为；报告保留原始测量，不做静默剔除。后续如需发布比较性结论，应采用 warm-up、固定重复次数、分位数统计和多个真实物理 GPU profile。

## 5. JSON oracle

新增 `tools/check-benchmark-report.js`。它验证：

1. schema 和 timestamp support；
2. 3 个 activate case 是否齐全；
3. 预期/实际 mask 是否分别为 `0x24`、`0x09`、`0x12`；
4. winner write bytes、tile 数、glyph draw/instance 数是否精确匹配 compiler contract；
5. CPU 和 GPU 字段是否为有效数值；
6. 每个 `expectations_match` 均为 true。

```bash
node tools/check-benchmark-report.js out/wgpu-benchmark.json
```

输出：

```text
noir benchmark JSON oracle passed
```

## 6. 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/frame-coalescing.scene.json

cd wgpu-verify
cargo build --release --bin noir_winit_host
cd ..

Xvfb :100 -screen 0 800x600x24 &
export DISPLAY=:100
export XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime
export WGPU_BACKEND=vulkan
./wgpu-verify/target/release/noir_winit_host \
  out/frame-coalescing.scene.json \
  --benchmark-report out/wgpu-benchmark.json

node tools/check-benchmark-report.js out/wgpu-benchmark.json
```

## 7. 结论与下一阶段

这套矩阵使 Noir 的完整最短路径具有数据输出：

> **compiler batch → winner-only GPU writes → merged tile mask → compiler glyph packet range → Placement Buffer draw → timestamped canvas pass → JSON oracle。**

本阶段基准的是已实现的 Coalesced Batch path，而不是在同一二进制中模拟旧 renderer。因此它证明每个优化后的 case 的真实 GPU/CPU 工作边界和 compiler contract 一致，但尚不构成“优化前后加速比”。下一阶段应实现 **Renderer Strategy Replay Matrix**：把 full redraw、packet-aware、action-aware、coalesced 四种 compiler-approved replay mode 固化为相同 Scene/batch 的独立 benchmark rows；每种模式做 warm-up + 多次 sample，输出中位数、P95 和真实物理 GPU profile registry 更新。 
