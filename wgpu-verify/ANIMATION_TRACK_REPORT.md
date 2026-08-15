# Noir 编译期 Animation Track 与 Frame-Clock Patch 验证

## 结论

Noir 现在可以把 release 动效表达为编译期 Animation Track，而不是运行时对象树上的通用 animation 行为。每个按钮都有一个固定的 80ms `ease-out` release 轨道；frame clock 在任意合法时间点只写该按钮 `QuadInstance` 的 `pos` 和 `color` 两个预分配字段。轨道抵达终点后，业务 action 才执行自己独立的局部 patch。

> **动画、hover/pressed 和业务状态不是同一个大运行时。它们是三类独立、可审计的 GPU 写入计划，分别作用于固定字段。**

## Racket 宏：将 release 定义为固定轨道

宏先从 Layout Plan 和 Event Map 得到按钮的 pressed/base keyframe，然后为每个按钮生成 `c-animation`。在当前 MVP 中，所有 release 轨道都固定为 80ms `ease-out`：

```racket
(c-animation
 (string->symbol (format "release-~a" (c-event-node-id event)))
 event 80 'ease-out)
```

第三按钮被降低为：

| 轨道属性 | 编译值 |
|---|---|
| Track ID | `release-advance-progress-button` |
| Node / instance slot | `advance-progress-button` / `396` |
| `pos_offset` / `color_offset` | `396` / `412` |
| Duration / easing | `80ms` / `ease-out` |
| `pos_from → pos_to` | pressed position → base position |
| `color_from → color_to` | pressed dark green → base green |
| Damage Plan | 第三按钮最大 rect `(411.33,230,174.67,46)` |

这些数据被写入 Scene JSON 的 `animation_tracks` 字段。宏并不只传“animation name”；它传递 keyframe、字段地址、持续时间、easing 和 Damage Plan，因此后端无需查 Scene tree 或计算布局。

## wgpu Frame Clock Patch

host 实现只接受经启动校验的 track。它以给定时钟值计算 `ease-out` 插值，并对两个固定 range 执行写入：

```rust
let t = 1.0 - (1.0 - elapsed_ms / duration_ms).powi(2);
let pos = lerp(track.pos_from, track.pos_to, t);
let color = lerp(track.color_from, track.color_to, t);
queue.write_buffer(instance_buffer, track.pos_offset, bytes(pos));
queue.write_buffer(instance_buffer, track.color_offset, bytes(color));
```

| Frame-clock 时间 | Ease-out `t` | 唯一 instance writes |
|---:|---:|---|
| `0ms` | `0.00` | `[(396,8),(412,16)]` |
| `40ms` | `0.75` | `[(396,8),(412,16)]` |
| `80ms` | `1.00` | `[(396,8),(412,16)]` |

即使在 0ms 和 80ms，验证器也明确写同一组字段，从而证明每一帧 frame clock 都具有确定、稳定的 GPU 写入边界。它不会写 glyph storage、progress slot `[228,232)` 或其它按钮实例。

## 与输入和业务 action 的完整序列

第三按钮的合成输入 `(500,250)` 命中 Event Map slot 2 后，真实验证执行下列路径：

```text
hover
  → color [412,16]
pressed
  → pos [396,8] + color [412,16]
frame clock 0ms / 40ms / 80ms
  → 每帧 pos [396,8] + color [412,16]
animation completed
  → advance-progress
  → size.x [228,4] + throughput Damage Plan
```

这次运行同时保留了前两次按钮点击的 text-run 更新：FPS 写 `[0,96)`，latency 写 `[96,192)`。因此所有实例化更新区间仍两两可解释、可审计。

## 自动化验证与视觉工件

Racket 测试验证轨道数量为 3，并检查第三轨道的 ID、slot、offset、duration、easing、pressed/base keyframe 与 Damage Plan。Rust/wgpu 回归验证：3 条 track 均被读取；第三 track 在 `0/40/80ms` 只有 `[(396,8),(412,16)]`；动画结束后 action 只写 `[(228,4)]`。

| 40ms 插值 | 80ms base 终点 | 完成轨道后执行 action |
|---|---|---|
| ![40ms](out/noir-animation-release-040ms.png) | ![80ms](out/noir-animation-release-080ms.png) | ![action](out/noir-animation-release-action.png) |

40ms 帧显示第三按钮视觉从 pressed 状态向 base 状态回弹；80ms 帧已恢复 base，但 progress 仍为 40%；最后 action 帧才使 progress 变为 72%。这说明动画结束与业务更新没有被混为一次全局 redraw。

## 当前边界与下一步

当前轨道固定为每个按钮一条 pos+color release animation，且使用合成帧时钟。它尚未处理多个并行轨道、取消、反向、可变 duration、真实 vsync timestamp 或独立 clip/opacity track。下一步最有价值的是**并发轨道调度与冲突证明**：当两个不同按钮同时有 hover/release track 时，编译器应证明它们的 instance byte ranges 不重叠；若同一 node 存在 hover 与 release 的字段冲突，则在编译期指定优先级或拒绝组合。
