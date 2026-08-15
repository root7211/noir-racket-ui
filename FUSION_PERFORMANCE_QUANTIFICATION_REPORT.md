# Compiler-Proved Batch Fusion：三请求 Baseline 与单请求 Fusion 的正式性能量化

**状态：** 已实现独立的三请求 baseline executor、compiler-proved 单请求 fusion executor、结构计数、真实 wgpu timestamp 测量、多轮统计和 X11/Vulkan正确性回归。

## 1. 要回答的问题

此前的 composite worklist 已验证一个 batch-local packet union 是可证明且可执行的，但 Settings Form 的旧 transaction path 本身已有单一 union slot，不能严谨回答“如果运行时真的发出三个独立 local request，fusion 能减少多少工作？”

本实验固定同一静态 `multi-field-event` fixture，构造两条只在 renderer request 形状上不同的路径：

| Executor | 输入 | RenderRequest | Packet compute | Queue submit |
|---|---|---:|---:|---:|
| **Baseline** | 同一 compiled batch / winner writes | 3 | 3 | 3 |
| **Fusion** | 同一 compiled batch / winner writes | 1 | 1 | 1 |

两条路径使用同一 Scene、同一 batch winner writes、相同的 tile union、相同的 glyph draw ranges、相同 wgpu/Vulkan adapter 和同一个 release binary。唯一允许不同的是 compiler-emitted request partition。

## 2. 编译期 baseline plan

`compile-composite-batch-worklists` 除了生成 fused packet union 以外，现在还为多成员 batch 输出 `baseline_requests`。每项包含 immutable worklist slot 与 tile IDs；三个 tile 集互不重叠，且其并集严格等于 fused batch tile union。

`fuse-commit` 的 artifact 如下：

| Baseline request | Local worklist | Tile IDs | Packet |
|---|---:|---:|---:|
| 1 | 3 | `[0,3]` | 3 |
| 2 | 4 | `[1]` | 6 |
| 3 | 5 | `[2]` | 9 |
| Fused request | 7 | `[0,1,2,3]` | `[3,6,9]` |

`fuse-reset` 的唯一差异是第一项使用 trigger tile `4`，融合 slot 为 `8`。Rust 在启动期重新验证 member slot 顺序、每个 baseline slot 的 field-local packet scope、tile无重叠性和 tile union exactness；因此 baseline executor 也没有运行时依赖发现或 tile合并。

## 3. 测量方法

实验在 **llvmpipe (LLVM 20.1.2, 256 bits) / Vulkan** 上运行。每个独立进程在采集前会预热两次 baseline 和两次 fusion CPU执行路径，并预热 timestamp path；随后采集测量。进行了 **15 次独立进程运行**，每次含 `fuse-commit` 与 `fuse-reset` 两个case。

CPU `event-to-submit` 计时**不包含**GPU timestamp query的同步 readback：CPU路径和GPU timestamp路径以相同executor单独运行，前者只度量从 winner writes 到最后一次 `queue.submit` 的时间，后者只用于GPU时间戳总和。此分离避免三请求baseline因三次同步readback而被人为放大。

## 4. 正确性与结构结果

所有 30 个 case sample 的 `expectations_match=true`。baseline与fusion均提交相同tile mask、相同4个tile、9个glyph draw和22个glyph placement实例。

| Case | Baseline requests / dispatches / submits | Fusion requests / dispatches / submits |
|---|---:|---:|
| Fuse Commit | 3 / 3 / 3 | 1 / 1 / 1 |
| Fuse Reset | 3 / 3 / 3 | 1 / 1 / 1 |

因此这是一个非推断的结构性结果：compiler proof 将三项独立field-local request压缩为一项，三个结构计数均减少 **66.7%**，且未扩大任何packet或tile覆盖范围。

## 5. 真实性能结果

下表是15轮独立运行的中位数；括号中为fusion相对baseline的变化。

| Case | CPU event-to-submit：baseline → fusion | GPU timestamp：baseline → fusion |
|---|---:|---:|
| Fuse Commit | 741.5 µs → 106.6 µs **(-85.6%)** | 817.9 µs → 541.7 µs **(-33.8%)** |
| Fuse Reset | 740.1 µs → 100.2 µs **(-86.5%)** | 896.6 µs → 564.5 µs **(-37.0%)** |

p95同样明显改善：Commit CPU为833.0→124.9 µs、GPU为1006.8→659.0 µs；Reset CPU为998.7→144.7 µs、GPU为1063.6→681.6 µs。

![正式fusion性能对比](wgpu-verify/out/fusion-benchmark-comparison.png)

## 6. 解释与边界

CPU收益主要来自少两次 command encoder / render pass / `queue.submit` 路径，GPU收益来自少两次 packet activity compute、少两次局部tile render pass及相应驱动调度。由于实验使用软件 Vulkan 适配器，绝对时间不应被外推到硬件GPU；但结构计数、compiler proof和同一adapter上的相对结果均是真实测量，不是模拟数据。

本实验也刻意保持 baseline tile partition 无重叠；否则fusion可能只是通过避免重复绘制得到“虚假”收益。当前结果证明 Noir 的关键命题：当编译期知道多field任务依赖的精确并集时，它能在不牺牲局部性和语义的条件下删除两条完整renderer提交路径。

## 7. 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" NOIR_ENTRY_MODULE="examples/composite-worklist-dashboard.rkt" \
  racket tools/export-dashboard.rkt out/composite-worklist-dashboard.scene.json
cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host

DISPLAY=:99 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  tools/sample_fusion_benchmark.sh \
  wgpu-verify/target/release/noir_winit_host \
  out/composite-worklist-dashboard.scene.json \
  15 wgpu-verify/out/fusion-benchmark-samples.jsonl

python3 tools/summarize_fusion_benchmark_samples.py \
  wgpu-verify/out/fusion-benchmark-samples.jsonl \
  wgpu-verify/out/fusion-benchmark-summary.json
python3 tools/plot_fusion_benchmark.py \
  wgpu-verify/out/fusion-benchmark-summary.json \
  wgpu-verify/out/fusion-benchmark-comparison.png
```

## 8. 下一步

下一步可把本实验机制提升到正常交互循环：当 event map 指向的 compiled batch 具有 `batch_fusion_proof` 时，普通输入路径可直接提交单一fusion request；而不带proof的多请求批次保持独立队列。随后值得研究的是跨batch fusion，但它必须先证明 state writes、tile masks、strategy和动画时序可交换，不能把未来帧的工作投机性合并。
