# GPU 常驻编译期 Packet Worklist 实验设计

## 假设

Noir 的 packet worklist 已在 Racket macro expansion 期完全确定。旧宿主虽将 worklist slot 作为 `RenderRequest` 的显式字段传递，但每次有非空 worklist 的局部重绘仍执行一次：

```rust
queue.write_buffer(worklist_buffer, 0, bytes_of(gpu_packet_worklist(...)))
```

这会在输入热路径额外发起 CPU→GPU buffer write，即使 payload 与上一帧或任意既有 compiler artifact 完全相同。

本实验将所有 compiler-emitted worklist 一次性打包为一个 GPU uniform table。运行时从 `RenderRequest.packet_worklist_index` 计算 dynamic uniform offset，并只执行 bind-group dynamic-offset 选择。工作列表内容不再在热路径上传。

## ABI

`GpuPacketWorklist` 固定为 160 bytes，包含 `count` 和最多 32 个 packet index。由于 dynamic uniform offset 需要满足当前 adapter 的 `min_uniform_buffer_offset_alignment`，每个表项的 slot stride 为：

```text
ceil(160 / min_uniform_buffer_offset_alignment)
    * min_uniform_buffer_offset_alignment
```

在现有 Vulkan/llvmpipe 环境通常为 256 bytes。因此每个 worklist 付出最多 96 bytes 的静态 padding，以换取事件期零 worklist payload upload。

## 编译期与运行时不变量

| 不变量 | 建立位置 | 运行时行为 |
|---|---|---|
| worklist index 是连续、已验证的 compiler slot | `compile-packet-worklists` 和 task-local lowering | 直接乘以静态 stride |
| 每个 worklist 不超过 32 packet | `gpu_packet_worklist` ABI assertion | 无动态扩容或范围扫描 |
| dynamic offset 对齐 adapter limit | GPU资源创建 | `set_bind_group(..., &[slot * stride])` |
| no-packets 的 worklist 为空 | compiler base list #2 | 跳过 compute dispatch |
| 每帧不会写 worklist uniform buffer | Rust activity encoder | 仅写 glyph/instance 的真实状态变更 |

## 正确性对照

启动期 scalar/subgroup differential 继续对 index 0 的 all-packets slot 做 activity 和 indirect buffer readback 比较。真实 X11 Settings Form oracle 再覆盖 field-local slot 3/4/5 与 transaction-local slot 6 的非空 dispatch。

## 性能测量边界

该优化主要减少 CPU encode-side submit 开销、驱动命令流与潜在 CPU→GPU 同步压力，而不改变 compute shader 的 workgroup count。因此 GPU timestamp 的理论变化应很小；关键观测量是 event-to-submit CPU 延迟和每次 request 的 `queue.write_buffer` 次数。现有 replay matrix 在 Settings Scene 中会进入 compiler-selected consistency 问题，故需要单独的 worklist microbenchmark，以测量固定非空 field/transaction slot 的 encode/submit 路径，而不混入策略 proof 的选择层。
