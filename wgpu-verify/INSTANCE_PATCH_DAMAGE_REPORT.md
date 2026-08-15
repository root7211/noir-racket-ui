# Noir 动态几何 Instance-Patch 与 Damage Plan 验证

## 结论

Noir 现已支持第三类动态因果路径。除了固定范围的 `text-run → glyph storage` 更新，DSL 中的受限 `progress` 节点可以在**不重新布局、不重写整个 instance buffer**的前提下，将状态动作编译为单一 `QuadInstance.size.x` 字段补丁与对应的 Damage Plan。

> `advance-progress` 将 `progress` 从 `40` 改为 `72`，并且唯一的几何 GPU 写入是 `queue.write_buffer(instance_buffer, 228, 4 bytes)`。

`228 = throughput` 固定 instance slot `220` + `size.x` 字段偏移 `8`。整个 `QuadInstance` 是 44 bytes，因而该 action 改写的是一个预分配实例的 **4/44 字节**，而不是重新上传 440-byte 的 10-instance buffer。

## 新 DSL 原语

动态几何使用受限的 `progress` 表面语法：

```racket
(state
 [frame-rate 60]
 [latency-ms 8]
 [progress 40])

(action advance-progress
 (set progress (+ progress 32)))

(progress #:id throughput #:dynamic progress #:max 100)
(button #:id advance-progress-button
        "Progress: 40 → 72"
        #:on advance-progress)
```

`progress` 有两个刻意的限制。它必须绑定一个整数状态，并且必须声明静态 `#:max`。它不会重新求解 row/column；只会缩放自己已经由 Layout Plan 分配的 `size.x`。这使语法保持简单，同时让 patch 地址、byte length 和最大可影响矩形在宏展开期可知。

## Racket 宏：从状态到精确 patch

`compile-layout-plan` 先为 `throughput` 分配完整可用 rect 和固定 instance slot：

```text
node              = throughput
instance_offset   = 220
full rect         = x=34, y=180, width=572, height=22
initial progress  = 40 / 100
initial size.x    = 0.715 NDC
```

只有在该 Layout Plan 已确定后，`compile-action-plans` 才生成实例绑定。`action-plan->datum` 将其降低为：

```racket
(instance-update 'instance-patch
                 'throughput 'progress
                 228 4 'size.x 0.017875)

(damage-region 'rect
               'throughput
               34.0 180.0 572.0 22.0
               220)
```

其中 `scale = (2 × 572 / 640) / 100 = 0.017875`，所以后端执行 action 后计算：

```text
size.x = next(progress) × scale = 72 × 0.017875 = 1.287 NDC
```

Damage Plan 不是运行时猜测的 dirty rect，而是进度条最大可覆盖区域。若使用增量 present / tiled renderer，它可直接作为保守重绘范围。

| Action | State write | Glyph write | Instance write | Damage Plan |
|---|---|---|---|---|
| `refresh-fps` | `frame-rate += 84` | `[0, 96)` | 无 | 无 |
| `refresh-latency` | `latency-ms += 7` | `[96, 192)` | 无 | 无 |
| `advance-progress` | `progress += 32` | 无 | `[228, 232)` | `throughput` 的 `34×180×572×22` rect |

## wgpu host：字段级写入

Rust host 不再把 geometry action 解释成重新构建 `Vec<QuadInstance>`。它验证 compiler contract 后只写 `size.x`：

```rust
if update.kind != "instance-patch" || update.field != "size.x" || update.byte_length != 4 {
    bail!("unsupported instance patch");
}

let value = next_state[&update.state];
let payload = (value as f32 * update.scale).to_le_bytes();
queue.write_buffer(instance_buffer, update.offset as u64, &payload);
```

同一 action 内，host 还验证：Damage Plan 数量等于 instance patch 数量；Damage Plan 的 `instance_offset` 等于 `patch.offset - 8`；Damage Plan 类型为非空 `rect`。它因此可以验证补丁既落在正确 field，也携带正确的局部视觉影响范围。

## 自动化验证

Racket 测试断言了以下契约：

| 编译期断言 | 结果 |
|---|---|
| Scene node / instance capacity | `10` / `10` |
| 动态节点域 | 2 个 text-run + 1 个 progress instance patch |
| progress 初始状态 | `40` |
| progress instance slot | `220` |
| `size.x` patch offset / length | `228` / `4` |
| patch scale | `0.017875` |
| Damage Plan | `(34, 180, 572, 22, 220)` |
| 固定 instance offset 序列 | `0, 44, …, 396` |

在 wgpu 0.20.1、Vulkan backend 和 llvmpipe CPU adapter 的端到端回归中，所有 action 均通过：

```text
host layout solver calls: 0

refresh-fps
  glyph writes    : [(0, 96)]
  instance writes : []

refresh-latency
  glyph writes    : [(96, 96)]
  instance writes : []

advance-progress
  glyph writes    : []
  instance writes : [(228, 4)]
  damage          : [("throughput", 34.0, 180.0, 572.0, 22.0)]
  state           : {progress: 72, frame-rate: 144, latency-ms: 15}
```

## 可视化工件

基线帧中，progress 的固定 rect 使用 40% 宽度。执行两个 text action 后，数字变为 `144` / `015`，但 progress 仍是 40%。执行 `advance-progress` 后，只改变同一 slot 的 `size.x`，进度条扩展到 72%，其他 geometry 与文字保持不变。

| 基线：40% | text actions 后：40% | progress action 后：72% |
|---|---|---|
| ![baseline](out/noir-progress-baseline.png) | ![text](out/noir-progress-refresh-latency.png) | ![progress](out/noir-progress-advance-progress.png) |

## 当前边界

这是为验证局部几何写入而选择的窄 MVP：只支持非负、受 `#:max` 限制的单轴 progress，patch 字段固定为 `size.x`。它尚未支持 transform、opacity、color、clip 或多个字段的原子 instance patch。下一阶段应扩展为声明式 `animate` / `style` 子集，但必须保持同一原则：每个动态属性都要在宏展开期给出稳定 instance field address、byte length、允许值域与 Damage Plan。
