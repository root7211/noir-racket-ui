# Noir Renderer Strategy Replay Matrix

**作者：Manus AI**  
**实现范围：** Rust 1.75、wgpu 0.20、winit 0.29.15 X11-only、Vulkan/llvmpipe。  
**目标：** 在同一 compiler Scene、相同 Coalesced Activate workload 和相同初始 GPU buffer 状态下，回放四种 renderer strategy，采集 warm-up 后的 GPU timestamp 与 CPU event-to-submit 分布，并导出可审计 JSON。

> 这不是把旧 renderer 作为另一个独立程序来测，而是将同一 host 的 canvas pass 固化为四种可解释的 replay mode。每个 mode 的状态起点、state transition、buffer update、tile mask 和 glyph draw 范围都可从 compiler Scene 或 host code 追踪。

## 1. 四种策略

| Mode | 事件写入语义 | Canvas submission | 文本提交 | 目的 |
|---|---|---|---|---|
| `full-redraw` | 完整 coalesced winner writes | 整个 canvas 的单一 full pass | 2 packet / 31 placement instances | 未裁剪 draw 基线 |
| `packet-aware` | 完整 coalesced winner writes | 所有 6 个 compiler tile | 仅 `glyph_packet_ranges`，2 draw / 6 dynamic instances | 隔离 glyph submission culling |
| `action-aware` | 仅 action 固定写集 | action `tile_ids` 的单 tile | FPS/latency 为 1 draw / 3 instances；progress 为 0 | 隔离 business-action 局部路径 |
| `coalesced` | release + action 的 winner-only batch 写集 | `merged_tile_ids` 的 2 tile | 与 action case 相同的局部 text range | 完整视觉语义下的最终路径 |

`action-aware` 的语义刻意不包含 button release，因为它用于量化业务 action 独立更新的下界；因此它不是 `coalesced` 的视觉等价替代。`coalesced` 才是完整 pointer-up activate 的正确渲染语义：同时恢复按钮和刷新业务内容。该差异通过各 row 的 `expected_write_bytes` 与 tile count 显式记录，而不是在结果中隐藏。

## 2. 可重复状态起点

Host 在初始化后保存三份 compiler-derived snapshot：

```rust
initial_state: HashMap<String, i64>,
initial_instances: Vec<QuadInstance>,
initial_glyph_bytes: Vec<u8>,
```

每个 warm-up 和 sample 开始前执行：

```rust
self.state = self.initial_state.clone();
self.instances.clone_from(&self.initial_instances);
self.queue.write_buffer(&self.instance_buffer, 0,
                        bytemuck::cast_slice(&self.instances));
self.queue.write_buffer(&self.glyph_buffer, 0,
                        &self.initial_glyph_bytes);
self.dirty_tiles = 0;
```

因此 progress state 不会在 repeated sampling 内累积，FPS/latency glyph ID 也不会继承前一次 action 的副作用。所有 sample 都从同一个 Scene 初始状态进入相同 batch workload。

## 3. 统计和 timestamp

CLI：

```bash
noir_winit_host SCENE.json \
  --replay-matrix REPORT.json \
  --warmup 2 \
  --samples 7
```

每个 workload × mode 先执行 `warmup_iterations` 次无 timestamp 回放，再执行 `sample_iterations` 次 timestamp 回放。报告对 CPU/GPU samples 分别输出：

| 字段 | 计算 |
|---|---|
| `min_ns` | 样本最小值 |
| `median_ns` | 排序后的中位数（下中位数） |
| `p95_ns` | `ceil(0.95 × N) - 1` 的顺序统计量 |
| `max_ns` | 样本最大值 |
| `mean_ns` | 算术均值 |

GPU 时间只包围 canvas pass 的 query 0–1；CPU 指标从 replay action/batch 入口到 canvas `queue.submit`。Timestamp map/readback 等待发生在 CPU 指标截取之后，因此不会混入 `cpu_event_to_submit_ns`。

## 4. JSON ABI

顶层 schema 为 `noir-wgpu-replay-matrix-v1`。每条 row 有：

```json
{
  "workload_id": "coalesced-activate-refresh-fps-button",
  "mode": "coalesced",
  "warmup_iterations": 2,
  "sample_iterations": 7,
  "submitted_tile_count": 2,
  "submitted_glyph_draw_count": 1,
  "submitted_glyph_instance_count": 3,
  "expected_write_bytes": 36,
  "gpu_elapsed_ns": { "median_ns": 274298.0 },
  "cpu_event_to_submit_ns": { "median_ns": 85081.0 }
}
```

`tools/check-replay-matrix.js` 验证 12 条 row（3 workloads × 4 modes）、每条 row 的固定 work metrics、分位数顺序、timestamp 支持和 sample count。它拒绝任意 renderer 回退，例如 full redraw 不再提交 31 placements，或 packet-aware 重新提交静态 title glyph。

## 5. 真实 Vulkan/llvmpipe 结果

运行环境：`llvmpipe (LLVM 20.1.2, 256 bits)`、Vulkan、Xvfb X11 surface、timestamp period 1 ns、warm-up 2、sample 7。结果来自 `out/replay-matrix.json`。

### 5.1 Progress activate

| Mode | Tile / glyph draws / instances | Writes | GPU median | CPU median |
|---|---:|---:|---:|---:|
| full-redraw | 1 / 2 / 31 | 28 B | 672,079 ns | 80,467 ns |
| packet-aware | 6 / 2 / 6 | 28 B | 566,256 ns | 95,569 ns |
| action-aware | 1 / 0 / 0 | 4 B | 279,731 ns | 59,074 ns |
| coalesced | 2 / 0 / 0 | 28 B | 373,460 ns | 81,212 ns |

### 5.2 FPS activate

| Mode | Tile / glyph draws / instances | Writes | GPU median | CPU median |
|---|---:|---:|---:|---:|
| full-redraw | 1 / 2 / 31 | 36 B | 684,366 ns | 98,691 ns |
| packet-aware | 6 / 2 / 6 | 36 B | 561,036 ns | 120,919 ns |
| action-aware | 1 / 1 / 3 | 12 B | 262,022 ns | 84,788 ns |
| coalesced | 2 / 1 / 3 | 36 B | 274,298 ns | 85,081 ns |

### 5.3 Latency activate

| Mode | Tile / glyph draws / instances | Writes | GPU median | CPU median |
|---|---:|---:|---:|---:|
| full-redraw | 1 / 2 / 31 | 36 B | 607,714 ns | 90,487 ns |
| packet-aware | 6 / 2 / 6 | 36 B | 571,427 ns | 101,872 ns |
| action-aware | 1 / 1 / 3 | 12 B | 242,099 ns | 48,795 ns |
| coalesced | 2 / 1 / 3 | 36 B | 294,295 ns | 79,137 ns |

这些行首先证明**工作量的离散收缩真实发生**：full redraw 每次提交 31 placement instances；packet-aware 在保留 6 tile 的情况下仅提交 6 dynamic placements；完整 coalesced activate 仅提交对应 metrics 的 3 placements；progress 完整路径完全没有 glyph draw。

在该软件 Vulkan 环境中，FPS GPU median 从 full redraw 的 684,366 ns 降至 coalesced 的 274,298 ns；latency 从 607,714 ns 降至 294,295 ns。上述差异仅应解释为该固定 llvmpipe workload 的真实测量，不应作为离散 GPU 或其他驱动的性能承诺。

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

Xvfb :102 -screen 0 800x600x24 &
export DISPLAY=:102
export XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime
export WGPU_BACKEND=vulkan

./wgpu-verify/target/release/noir_winit_host \
  out/frame-coalescing.scene.json \
  --replay-matrix out/replay-matrix.json \
  --warmup 2 \
  --samples 7

node tools/check-replay-matrix.js out/replay-matrix.json
```

## 7. 后续

Replay Matrix 已把 Noir 的优化链转化为同 Scene、同 workload、同 host 的可比较时间分布。下一阶段不应简单增加更多 mode，而应把该 Matrix 接入 **profile calibration registry**：对真实物理 Vulkan GPU 按固定重复次数采样，冻结 device/vendor/driver metadata、timestamp period、median/P95 与 work metrics，并让 Racket cost model 依据 profile 决定 fragment、lower-range 或 full-tile strategy。 
