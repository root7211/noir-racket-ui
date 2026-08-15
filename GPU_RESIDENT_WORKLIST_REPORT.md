# Noir GPU 常驻编译期 Worklist：黑魔法实验报告

**状态：** 已实现、已通过真实 X11/Vulkan 正确性验证，并完成十二轮独立真实 wgpu 基准采样。  
**研究问题：** 当 Racket 编译器已在 build time 固定 packet worklist 时，是否还应在每一个 render request 的热路径上传同一份 160-byte worklist uniform payload？

## 1. 核心结论

> **不应上传。** packet worklist 是不可变的 compiler artifact，应像 glyph placement plan、packet descriptor 与 indirect layout 一样在宿主初始化时常驻 GPU。运行时只把 `RenderRequest.packet_worklist_index` 解释为 dynamic uniform offset。

本实验删除了非空 worklist 局部重绘中的 `queue.write_buffer(worklist_buffer, ...)`。宿主启动时将全部 compiler worklist 一次性打包到一个 uniform buffer；每次 compute dispatch 使用预证明的 slot 乘以对齐 stride，作为 bind group 的 dynamic offset。X11 Settings Form 回归证明 field-local slot 3/4/5 与 transaction-local slot 6 仍然选择了正确 packet 子集。

性能数据并不支持把该结果夸大为“GPU shader 更快”。compute shader、packet 数量与 workgroup 数均没有变化；这项优化移除的是 CPU/driver 命令流中的 worklist payload upload。真实 llvmpipe/Vulkan 数据显示 transaction-heavy `apply-all` 的 CPU event-to-submit 中位数改善 **3.07%**，GPU timestamp 中位数改善 **6.75%**；其他小型任务存在正负混合变化，符合软件 Vulkan 与独立进程采样的噪声特征。

## 2. 实现

### 2.1 固定 ABI 与驻留表

`GpuPacketWorklist` 的 ABI 未改变：160 bytes，包含 `count` 和最多 32 个 packet index。为了满足 `wgpu` dynamic uniform offset 的 adapter 对齐约束，宿主将 payload stride 计算为：

```text
stride = ceil(160 / min_uniform_buffer_offset_alignment)
       × min_uniform_buffer_offset_alignment
```

本次真实 Vulkan 运行中的 stride 为 **256 bytes**。Settings Scene 有 7 个 worklist，故常驻 table 占用 `7 × 256 = 1792 bytes`；相对于每次输入的 worklist upload，它以很小的静态 padding 换取热路径零上传。

| 旧路径 | 新路径 |
|---|---|
| `RenderRequest.slot` → 查表 → `queue.write_buffer(160 B)` → bind group | `RenderRequest.slot` → `slot × 256` → dynamic offset bind group |
| 每次非空 request 发起 CPU→GPU payload write | 初始化时一次性上传 7 个 compiler artifact |
| worklist buffer 可变 | worklist table 在运行期不可变 |
| scope 正确性依赖本帧 write 的先后 | scope 仅由 compiler slot 决定 |

### 2.2 关键执行代码

```rust
let dynamic_offset = (worklist_index as u32)
    .checked_mul(activity.worklist_stride)
    .expect("compiler worklist dynamic offset overflow");
pass.set_bind_group(0, &activity.bind_group, &[dynamic_offset]);
pass.dispatch_workgroups(worklist.packet_indices.len() as u32, 1, 1);
```

bind group 的 uniform binding 改为 `has_dynamic_offset: true`，并以一个 160-byte binding window 绑定常驻表。首次实现使用 entire binding 会使 wgpu 把最大 dynamic offset 视为零；真实 validation error 已被捕获并修正为 `BufferBinding { offset: 0, size: 160 }`。这说明动态 offset 的 buffer binding range 是该 ABI 的必要组成部分，而不是可选细节。

## 3. 正确性验证

| 检查 | 结果 | 证据 |
|---|---|---|
| Rust release build | 通过 | Rust 1.75 / wgpu 0.20，只有既有非阻塞 warning |
| packet scalar differential | 通过 | scalar/reference activity 与 indirect readback 相等 |
| 静态热路径审计 | 通过 | worklist buffer 不再带 `COPY_DST`；activity encoder 无 worklist `queue.write_buffer` |
| X11 Settings Form | 通过 | 真实键盘事件、真实 wgpu/Vulkan 渲染与 oracle 全部通过 |
| field-local worklist | 通过 | slot 3/4/5 分别 dispatch `[3]`、`[6]`、`[9]` |
| transaction-local worklist | 通过 | Apply All slot 6 dispatch `[3, 6, 9]` |
| no-packets | 通过 | slot 2 保持 `compiler-empty` compute skip |

真实宿主启动日志：

```text
compiler resident packet worklist table: lists=7 payload_bytes=160 stride_bytes=256 hot_path_uploads=0
```

真实 X11 表单日志：

```text
packet-activity-dispatch worklist=field-sample-interval-row$field index=3 packets=[3]
packet-activity-dispatch worklist=field-alert-threshold-row$field index=4 packets=[6]
packet-activity-dispatch worklist=field-batch-size-row$field index=5 packets=[9]
packet-activity-dispatch worklist=transaction-apply-all index=6 packets=[3, 6, 9]
```

## 4. 性能实验

### 4.1 方法

实验使用相同 Settings Scene、相同 X11 display (`:99`)、同一 `llvmpipe (LLVM 20.1.2, 256 bits)` Vulkan adapter。优化前的 release binary 在实现变更前保存；优化后 binary 由同一源码树重新 release build。每个版本启动独立真实 wgpu 进程 **12 次**，每次执行完全相同的 compiler-emitted coalesced activation benchmark。每一行均要求 `expectations_match=true`。

图表：

![十二轮真实 Vulkan/llvmpipe 基准对比](wgpu-verify/out/resident-worklist-comparison.png)

### 4.2 中位数结果

| 任务 | CPU event-to-submit 中位数（旧→新） | 变化 | GPU timestamp 中位数（旧→新） | 变化 |
|---|---:|---:|---:|---:|
| alert-threshold apply | 13,049.5 → 13,423.3 µs | +2.86% | 387.0 → 340.6 µs | -11.99% |
| **Apply All transaction** | **188.6 → 182.8 µs** | **-3.07%** | **720.6 → 671.9 µs** | **-6.75%** |
| batch-size apply | 122.2 → 113.6 µs | -7.01% | 317.3 → 325.7 µs | +2.66% |
| reset-all transaction | 124.7 → 109.9 µs | -11.91% | 617.5 → 643.4 µs | +4.19% |
| sample-interval apply | 91.0 → 92.9 µs | +2.12% | 297.3 → 306.9 µs | +3.23% |

所有 5 个任务在两个版本中均保持 compiler tile mask、winner writes 与 submission contract 一致。

## 5. 解释与研究价值

`apply-all` 是最具代表性的非空复合 worklist 路径：batch refs 为 `[Transient(11), Transaction(0)]`，worklist slots 为 `[2, 6]`，最终 dispatch 的 transaction-local payload 是 `[3, 6, 9]`。在这条路径上，常驻表消除了每次 request 重新上传这个固定三 packet 列表的行为，并在两项中位数指标上出现改善。

但本实验运行于 llvmpipe，且每次样本创建独立 wgpu 进程。CPU 数十微秒级结果与 GPU 数百微秒级 timestamp 都会受到软件后端调度、管线初始化残余、host OS 调度和 readback 行为的影响。因此，本报告只主张：

1. **语义收益已被证明。** worklist 现在是 GPU-resident immutable compiler artifact；
2. **热路径写入被静态且运行时证据双重证明消除；**
3. **真实 transaction 路径出现可观测改善，但当前数据不足以承诺所有 workload 的统一速度提升。**

这正符合 Noir 的研究方向：先消除不必要的动态工作，再通过特定 workload 的稳定基准评估是否值得进一步专门化。

## 6. 下一项黑魔法研究

下一步应实现 **compiler-proved composite worklist**。当前 `RenderRequest` 队列会保留不同 local slot 的边界；如果一个静态 coalesced batch 同时影响两个 field-local worklist，编译器可在 macro expansion 期生成它们的 canonical packet union、证明无额外 packet 被包含，并发出一个新的 batch-local worklist slot。运行时再将两个 renderer request 压缩为一个 dynamic-offset compute dispatch。

其不可妥协的证明条件是：复合 slot 必须等于已知 constituent slot 的去重有序并集，而不能包含任何不属于其成员任务 dependency 的 packet。这样才能把“减少 submit 数”与“Noir 绝不扩大 GPU 写范围”的原则同时保留下来。

## 7. 可复现命令

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host
tools/verify_settings_form.sh

# 保留优化前二进制后，在同一X11/Vulkan环境采样。
DISPLAY=:99 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  tools/sample_resident_worklist_benchmark.sh \
  <baseline-binary> out/settings-dashboard.scene.json 12 \
  wgpu-verify/out/baseline.jsonl
DISPLAY=:99 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  tools/sample_resident_worklist_benchmark.sh \
  wgpu-verify/target/release/noir_winit_host out/settings-dashboard.scene.json 12 \
  wgpu-verify/out/optimized.jsonl
python3 tools/summarize_resident_worklist_samples.py \
  wgpu-verify/out/baseline.jsonl wgpu-verify/out/optimized.jsonl \
  wgpu-verify/out/comparison.json
```
