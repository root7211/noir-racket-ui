# Noir 双动态绑定与不重叠 GPU 区间验证

## 结论

本实验已将 Noir 从“一个状态变化对应一个局部 GPU 写入”的单变量演示，扩展为**两个相互独立的状态因果域**。Racket 宏在展开期为 `fps` 和 `latency` 两个动态文本节点分配连续、不重叠的 glyph storage；Rust/wgpu host 分别执行两个动作，并验证每次只改写对应的一个区间。

> **`refresh-fps` 只写 `[0, 96)`；`refresh-latency` 只写 `[96, 192)`；两次动作均不重写 instance buffer，也不创建新 pipeline。**

## DSL：两个状态、两个 action

```racket
#lang noir/ui

(noir-app
 (state
  [frame-rate 60]
  [latency-ms 8])

 (action refresh-fps
  (set frame-rate (+ frame-rate 84)))

 (action refresh-latency
  (set latency-ms (+ latency-ms 7)))

 (column #:id dashboard #:gap 16 #:padding 24 #:background dark
   (text #:id title "NOIR CAUSAL GPU DASHBOARD")
   (row #:id metrics #:gap 12
     (text #:id fps #:dynamic frame-rate #:max-chars 3)
     (text #:id latency #:dynamic latency-ms #:max-chars 3))
   (row #:id actions #:gap 12
     (button #:id refresh-fps-button "FPS: 60 → 144" #:on refresh-fps)
     (button #:id refresh-latency-button "Latency: 8 → 15" #:on refresh-latency))))
```

`#:max-chars 3` 是一个资源许可证：每个动态数字有 3 个固定 glyph slot，每 slot 占 32 字节。两个绑定因此各占 96 字节。

## 宏的关键逻辑

Racket compiler 在 `collect-glyph-bindings` 中按稳定 Scene tree order 单调分配 offset，并在 `assert-non-overlapping-bindings!` 中把不重叠性变成显式 compile-time invariant：

```racket
(binding (c-binding node-id state-id offset byte-length glyph-count))
(loop remaining-nodes (+ offset byte-length) bindings)

(when (< next-offset previous-end)
  (raise-syntax-error 'text "overlapping glyph buffer range" ...))
```

动作计划随后按依赖状态过滤 binding。`refresh-fps` 只匹配 `frame-rate`；`refresh-latency` 只匹配 `latency-ms`。因此生成的 JSON 不依赖运行时 tree scan：

| Action | 状态写入 | GPU 节点 | Buffer range | Glyph 数 |
|---|---|---:|---:|---:|
| `refresh-fps` | `frame-rate += 84` | `fps` | `[0, 96)` | 3 |
| `refresh-latency` | `latency-ms += 7` | `latency` | `[96, 192)` | 3 |

## wgpu 的关键逻辑

后端不根据节点 ID 搜索场景，也不重新计算布局。它只消费 action 自带的 `gpu_updates`：

```rust
for update in &plan.gpu_updates {
    let value = next_state[&update.state];
    let payload = digit_payload(value, update.glyph_count)?;
    queue.write_buffer(glyph_buffer, update.offset as u64, &payload);
    audit.glyph_writes_after_initial.push((update.offset, payload.len()));
}
```

`all_gpu_updates` 还会按 offset 排序并检查相邻 range；若 `right.offset < left.offset + left.byte_length`，后端直接失败。这使编译期和后端都各自验证一次地址隔离。

## 实测结果

测试环境为 wgpu 0.20.1、Vulkan backend、Mesa llvmpipe CPU adapter。它不是物理 GPU 性能 benchmark，但执行了真实 device 请求、storage buffer 写入、WGSL storage buffer 读取、instance draw、离屏 texture render、copy-to-buffer 与 map readback。

```text
Noir Dual Binding → wgpu isolation verification
  scene nodes     : 8
  instance budget : 8 (used 8)
  glyph budget    : 6
  global glyph steps: 2
  exact bindings  : [("fps", 0, 96), ("latency", 96, 96)]

  action refresh-fps
    gpu writes  : [(0, 96)]
    state       : {frame-rate: 144, latency-ms: 8}
    checksum    : 29088744 → 29714376

  action refresh-latency
    gpu writes  : [(96, 96)]
    state       : {frame-rate: 144, latency-ms: 15}
    checksum    : 29714376 → 29289840

  shared pipelines : 1
```

三个帧工件与 audit 对齐：首次 action 后左侧 `fps` tile 变化、右侧 `latency` tile 保持；第二次 action 后右侧 `latency` tile 变化、左侧已更新的 `fps` tile 保持。

| 基线：`60` / `8` | `refresh-fps` 后：`144` / `8` | `refresh-latency` 后：`144` / `15` |
|---|---|---|
| ![baseline](out/noir-dual-baseline.png) | ![fps](out/noir-dual-refresh-fps.png) | ![latency](out/noir-dual-refresh-latency.png) |

## 已实现的可验证性质

| 性质 | 验证点 |
|---|---|
| 状态声明完整 | `frame-rate` 与 `latency-ms` 在宏展开期被收集；未声明的动态状态报错。 |
| 动作引用完整 | 两个按钮的 `#:on` 都必须引用已声明 action。 |
| 资源预算有界 | `glyph_capacity = 6`，即 6 个 glyph slot、192 字节 storage。 |
| 区间不重叠 | Racket macro 和 Rust host 都检查 `[0,96)` 与 `[96,192)` 不相交。 |
| 局部状态更新 | 每条 action 仅写一个自己的状态；后端检查未写状态保持不变。 |
| 局部 GPU 更新 | `refresh-fps` 仅审计到 `(0, 96)`；`refresh-latency` 仅审计到 `(96, 96)`。 |
| 渲染资源复用 | 动作后 instance-buffer 写入为 0，shared pipeline 数量仍为 1。 |
| 可见效果 | 两次动作均使相邻两帧 checksum 改变，且视觉变化局限于相应 tile。 |

## 下一步

现在不应立即增加复杂 widget。更有价值的下一步是将颜色编码的数字 slot 替换为真实 glyph atlas：每一个 `gpu-update` 仍写相同 `[offset, offset + byte_length)` 区间，但 payload 改为 glyph quad 的 atlas UV、advance 和纹理索引。这样可以验证相同因果/资源模型在真实文本渲染中依然成立。
