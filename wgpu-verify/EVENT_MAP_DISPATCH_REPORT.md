# Noir 编译期 Event Map、固定 Hit-Test 与 Action Dispatch 验证

## 结论

Noir 现在具备从输入到局部 GPU 更新的完整闭环。按钮不再只是带有 `#:on` 属性的静态 Scene node；Racket 宏会将每个按钮降低为不可变 Event Map entry，携带稳定 `slot`、像素 hit rect、`z_index` 和 `action_id`。wgpu host 接收 pointer 坐标后，先查询 Event Map，再使用命中 entry 的 action id 分发既有的 text-run / instance-patch 计划。

> **运行时没有按钮 tree walk、没有动态 layout hit-test、没有手写 action dispatch 表。输入只在编译期生成的 Event Map 中命中一个矩形。**

## Racket 宏：按钮到 Event Map

现有按钮语法保持极简：

```racket
(button #:id advance-progress-button
        "Progress: 40 → 72"
        #:on advance-progress)
```

宏已经拥有按钮的稳定 ID 与其通过 `compile-layout-plan` 得到的 rect。因此 `compile-event-map` 仅按稳定 DFS 顺序过滤 button node，将对应 Layout Entry 直接写入 Event Map：

```racket
(c-event slot
         (c-node-id node)
         (hash-ref (c-node-props node) 'on)
         (c-layout-x layout)
         (c-layout-y layout)
         (c-layout-width layout)
         (c-layout-height layout)
         slot)
```

这个 MVP 选择 `slot == z_index`。若未来有重叠 clickable overlay，host 将选择最大 `z_index`；目前稳定 DFS 顺序已足以给出可复现、可审计的优先级。

| Slot / z-index | Node | Hit rect（像素） | Action |
|---:|---|---|---|
| 0 | `refresh-fps-button` | `(46, 230, 174.67, 46)` | `refresh-fps` |
| 1 | `refresh-latency-button` | `(228.67, 230, 174.67, 46)` | `refresh-latency` |
| 2 | `advance-progress-button` | `(411.33, 230, 174.67, 46)` | `advance-progress` |

这些 binding 被作为 `event_map` 放进 Scene JSON，与 `layout_plan`、`actions` 一起导出。

## wgpu host：固定 hit-test

host 的 hit-test 是线性、可预测的矩形过滤。它不观察 Scene root：

```rust
fn hit_test(event_map: &[EventBinding], x: f32, y: f32) -> Option<&EventBinding> {
    event_map.iter()
        .filter(|event| x >= event.x && x < event.x + event.width
                      && y >= event.y && y < event.y + event.height)
        .max_by_key(|event| event.z_index)
}
```

在初始化阶段，host 验证 Event Map slot 连续、node 不重复、rect 非空，并检查每个 `action` 都出现在 compiler 生成的 action plan 表中。它还测试 `(620, 340)` 不命中任何 binding，以排除无效 hit rect。

验证器不再调用 `dispatch_action("advance-progress")`。它将合成指针坐标交给 `hit_test`，取得 `hit.action` 后才调用 dispatcher：

```rust
let hit = hit_test(&scene.event_map, pointer_x, pointer_y)?;
let action_id = hit.action.as_str();
let action = scene.actions.get(action_id)?;
let (next_state, audit) = dispatch_action(..., action_id, action)?;
```

## 端到端验证

运行环境为 wgpu 0.20.1、Vulkan backend、llvmpipe CPU adapter。三次合成 pointer-down 分别命中三个不同 slot，并触发已验证的局部 GPU 写入。

```text
pointer (100, 250)
  hit slot 0 / refresh-fps-button → refresh-fps
  glyph writes    : [(0, 96)]
  instance writes : []

pointer (280, 250)
  hit slot 1 / refresh-latency-button → refresh-latency
  glyph writes    : [(96, 96)]
  instance writes : []

pointer (500, 250)
  hit slot 2 / advance-progress-button → advance-progress
  glyph writes    : []
  instance writes : [(228, 4)]
  damage          : [("throughput", 34.0, 180.0, 572.0, 22.0)]
```

因此每条输入路径都满足下述因果约束：

| 输入 | 命中 action | 状态变更 | 唯一 GPU 数据写入 |
|---|---|---|---|
| `(100, 250)` | `refresh-fps` | `frame-rate: 60 → 144` | glyph `[0, 96)` |
| `(280, 250)` | `refresh-latency` | `latency-ms: 8 → 15` | glyph `[96, 192)` |
| `(500, 250)` | `advance-progress` | `progress: 40 → 72` | instance `size.x` `[228, 232)` |

所有路径继续满足 `host layout solver calls: 0` 与 `shared pipelines: 1`。输入只选择 action；action 决定预编译的局部 patch；host 不求解新的 UI tree。

## 可视化工件

基线有三块固定按钮和 40% 的进度条。依次通过三个 Event Map hit 执行 action 后，数字变为 `144` / `015`，最后 progress 扩展至 72%。

| 基线 | 由 slot 0 / 1 输入更新文本 | 由 slot 2 输入更新进度条 |
|---|---|---|
| ![baseline](out/noir-event-baseline.png) | ![text](out/noir-event-refresh-latency.png) | ![progress](out/noir-event-advance-progress.png) |

## 当前边界与下一步

这是 pointer-down 的桌面 MVP，未处理多指、drag、键盘 focus、pointer capture、滚轮或 accessibility semantics。下一阶段最有价值的扩展是 `hover` / `pressed` 状态：它们同样应由 Event Map 选择一个稳定 node，再执行编译期确定的颜色或 opacity `instance-patch`。不要先增加复杂事件传播模型；先验证 transient input state 也能保持局部、可审计的字段写入。
