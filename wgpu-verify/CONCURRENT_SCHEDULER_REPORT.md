# Noir 并发 Animation Track 调度与编译期字段冲突证明

## 结论

Noir 现已把 UI 更新从“若干局部 patch”提升为**带写集和冲突证明的编译期调度计划**。Racket 宏为 release、hover、pressed 与业务 action 生成固定 GPU byte ranges、任务优先级与 Conflict Graph。wgpu host 在启动时复核每条冲突边；在同帧执行时根据 winner 显式屏蔽低优先级任务的重叠字段，而不依赖不可审计的写入顺序。

> **同帧 UI 更新不再是“谁后写谁赢”；它是“编译器给出写集、冲突边和 winner，runtime 按计划只提交未冲突字段”。**

## 编译期 Frame Schedule

宏将四类更新统一降低为 `frame-task`：

| Kind | Priority | 示例写集 |
|---|---:|---|
| `release` | 10 | `pos[396,404)`、`color[412,428)` |
| `hover` | 20 | `color[324,340)` 或目标按钮 color |
| `pressed` | 30 | `pos[...]`、`color[...]` |
| `action` | 40 | `glyph[...]` 或 `size.x[228,232)` |

当前 Dashboard 由宏展开成 **12 个 scheduler task**：3 release、3 hover、3 pressed、3 action。每一个 task 只携带固定 offset 和 byte length；不包含 Scene tree traversal、对象指针或运行时布局表达式。

对应的 Racket 核心形态为：

```racket
(c-frame-task task-id kind priority
              '((offset byte-length) ...))
```

业务 action 的 instance write 仍从 Layout Plan 计算：进度条 `advance-progress` 的唯一写集是 `((228 4))`；而 `hover-refresh-fps-button` 的唯一写集是 `((324 16))`。

## 编译期 Conflict Graph

宏对所有 task 的 byte range 两两求交。若范围重叠，生成 `conflict-edge(left, right, winner, overlaps)`；winner 先由 priority 决定，同 priority 时以稳定 task ID 决定。因此生成结果对源码和宏展开顺序稳定。

本实验含 **9 条冲突边**。最关键的一条为：

| Left | Right | Overlap | Winner |
|---|---|---|---|
| `release-advance-progress-button` | `hover-advance-progress-button` | `color[412,428)` | `hover-advance-progress-button` |

这条边说明同一按钮在 release animation 与 hover 同时活跃时，hover 的 priority `20` 大于 release 的 `10`，因此 hover 取得 color 字段所有权。release 的 position 字段 `[396,404)` 不冲突，仍允许同帧更新。

## wgpu 同帧调度

验证器读取 Scene JSON 后检查：task 数为 12、task ID 唯一、全部 range 非空、Conflict Graph 的 overlap 与真实 range 交集一致，并且每条 winner 的 priority 不低于冲突双方。对关键 release/hover edge，host 要求 overlap 必须正好是 `[412,16]`，winner 必须是 hover task。

在 40ms 帧，验证器按编译优先级执行：

```text
advance-progress                priority 40  → [228,4]
hover-refresh-fps-button        priority 20  → [324,16]
release-advance-progress-button priority 10  → [396,8]
                                     color [412,16] 被冲突图显式屏蔽
```

最终有效写集为：

```text
[(228,4), (324,16), (396,8)]
```

三段范围互不重叠。第一段扩展 progress，第二段使第一按钮进入 hover 色，第三段使第三按钮沿 release 动画改变 position。第三按钮 color 的 release write 则被 scheduler 丢弃，因为高优先级 hover task 拥有这个字段。

## 真实渲染验证

回归运行使用 wgpu 0.20.1、Vulkan backend 和 llvmpipe CPU adapter。它通过 Racket 宏测试与无警告 Rust 编译，报告：

| 验证项 | 结果 |
|---|---|
| 预编译 scheduler tasks / conflicts | `12 / 9` |
| Host layout solver calls | `0` |
| 40ms 有效并发 writes | `[(228,4),(324,16),(396,8)]` |
| release / hover winner | `hover-advance-progress-button` |
| 文字区间 | FPS `[0,96)`；latency `[96,192)` |
| 共享 render pipeline | `1` |

| 40ms 同帧调度 | 80ms release 终点 |
|---|---|
| ![concurrent](out/noir-schedule-concurrent-040ms.png) | ![endpoint](out/noir-schedule-release-080ms.png) |

40ms 帧同时显示 progress 变宽、第一按钮 hover 和第三按钮的 release position 变化。80ms 时第三按钮恢复 base visual，而 progress 与第一按钮 hover 均保持，说明各固定 slot 的并发更新没有互相污染。

## 当前边界与下一步

当前 scheduler 在 host 侧用一个小型合成测试显式应用 winner mask；它尚未生成 GPU command encoder 分组、未涵盖多个相同 priority 的独立 track，也未实现真正的 pointer capture 或可取消任务。下一步应实现 **Damage Region 合并 + Tile/Scissor render scheduling**：把当前每个 action/track 的 Damage Plan 编译为同帧不重叠或可合并的 scissor rectangles，验证 compositor 不必每帧绘制整个 640×360 target，而只提交受影响 tile。
