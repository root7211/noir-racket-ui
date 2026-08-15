# Noir `#lang noir/ui` 组件宏内联

**作者：Manus AI**  
**范围：** `metric-card`、`control-button`、基础 node parser、通用 render damage lowering 与组件化 dashboard 示例。  
**目标：** 让用户以高层组件组合 UI，而 compiler 在宏展开期把组件完全降低为既有 rendering primitives；runtime 不持有 component object、virtual tree、样式解析器或通用 diff。

> Component 是构建期语法，不是运行时对象。组件调用在 `parse-node` 递归前展开为 column、text、button 等已有原语，因此 layout、glyph placement、Event Map、tile selection、coalesced batch 和 strategy proof 全部复用同一条已验证的编译路径。

## 1. 新增 surface syntax

| 组件 | 受限静态参数 | 内联为基础原语 |
|---|---|---|
| `metric-card` | `#:id`、`#:label`、`#:dynamic`、`#:max-chars`，可选 `#:gap`/`#:padding` | `column` + 静态 label `text` + 固定长度动态 `text-run` |
| `control-button` | `#:id`、`#:label`、`#:on`，可选 `#:width`/`#:height`/`#:grow` | 已有 `button` primitive |

例如：

```racket
(metric-card #:id fps-card #:label "FPS"
             #:dynamic frame-rate #:max-chars 3)

(control-button #:id component-refresh-fps
                #:label "REFRESH FPS" #:on refresh-fps #:width 140)
```

`metric-card` 在 expand time 等价于：

```racket
(column #:id fps-card #:gap 6 #:padding 8
  (text #:id fps-card$label "FPS")
  (text #:id fps-card$value #:dynamic frame-rate #:max-chars 3))
```

`control-button` 等价于：

```racket
(button #:id component-refresh-fps #:width 140
        "REFRESH FPS" #:on refresh-fps)
```

派生 child IDs 用 `outer-id$label` 和 `outer-id$value` 形成 compiler-controlled stable namespace。调用者在同一 UI tree 显式声明相同 ID 时，既有 `register-id` duplicate check 会在宏展开期拒绝。

## 2. 内联算法与性能边界

组件 parser 只接受 literals 和 identifiers：label 必须是静态 string，dynamic state/action 必须是 identifier，数值属性必须是非负 compile-time literal。它用 `datum->syntax` 构造基础 form，并立即递归调用同一个 `parse-node`。因此不新增 C IR tag，也不引入第二个 layout solver 或 component-specific backend。

| 阶段 | `metric-card` 的结果 | `control-button` 的结果 |
|---|---|---|
| Parser | 外层 column、static/dynamic text nodes | base button node |
| Text lowering | page-1 static label shaping；page-0 fixed dynamic glyph slots | 不改变 glyph ABI |
| Layout plan | 三个固定 layout entries | 一个固定 button instance offset |
| Event/animation | 无额外 runtime component state | 既有 Event Map、hover/pressed/release track |
| Tile/batch | 动态 text binding 进入 action-specific tile/packet plan | 按既有 event rectangle 生成 task tile IDs/batches |

## 3. 组件化示例

`examples/component-dashboard.rkt` 只使用 component surface syntax 来定义两个 metrics cards 和三枚 control buttons。导出的 Scene JSON 中**不存在** `"tag":"metric-card"` 或 `"tag":"control-button"`；它们已经成为可审计的基础 tags 和 IDs：

```text
fps-card
fps-card$label
fps-card$value
latency-card
latency-card$label
latency-card$value
component-refresh-fps
component-refresh-latency
component-advance-progress
```

为了让组件不受原 dashboard 名称约束，Render Schedule 的动态 geometry damage 也从固定 `throughput` lookup 改为遍历每个 `c-action-plan-instance-updates` 的真实 layout。`progress` 原语因而可由任意 component-derived stable ID 使用，仍只写其固定 `size.x` 字段。

## 4. 验证结果

`tests/run.rkt` 新增 compiler oracle，确认 component Scene 有 3 个 dynamic nodes、两个 metric card 的 derived static/value IDs、三个 base Event Map button IDs、动态 GPU patch 节点 `fps-card$value` / `latency-card$value`，以及 `component-throughput` 的 instance patch binding。原 dashboard 的所有 glyph/tile/coalescing assertions 也同时通过。

`tools/verify_component_dashboard.sh` 可重复执行以下真实路径：

1. 以 `NOIR_ENTRY_MODULE=examples/component-dashboard.rkt` 导出 Scene；
2. 断言 component tag 不泄漏到 runtime JSON；
3. 在 Xvfb + Vulkan/llvmpipe 的 wgpu Surface 中启动 host；
4. 用 `xdotool` 依次点击三枚 `control-button`；
5. 断言 compiler-generated coalesced batches 出现，FPS/latency 各写 12-byte glyph ID slots，progress 只写 `[448..452)` 的 4-byte instance field。

该脚本已经通过。这表明 component layer 不是 mock UI，而是已进入同一条真实 GPU/X11 event loop。

## 5. 当前刻意限制

组件仍是受限宏，不支持 runtime-prop spread、任意 children slot、反射或可变 style object。这些限制是性能模型的一部分：每个组件调用必须在 expand time 确定基础 node 数、stable IDs、state binding、glyph capacity、instance offsets 和 event rectangles。后续可以添加更多**静态**组件（例如 `status-pill`、`list-row`、`panel`），但应保持“组件内联后只剩基础原语”的规则。 
