# Noir `repeat/ui` 静态重复宏

**作者：Manus AI**  
**范围：** `#lang noir/ui` 的 child-splicing parser、`repeat/ui` datum table、组件内联、固定 CPU monitor showcase。  
**目标：** 为 GUI 提供列表/重复组件能力，同时保持 Noir 的运行时零遍历、零 key reconciliation、零动态 layout/diff 的约束。

> `repeat/ui` 是 macro expansion 的 child splice，不是 runtime node。固定表中的每一行在编译期替换模板 identifiers，并由既有 parser 继续降低为基础 primitives。

## 1. 语法

```racket
(repeat/ui ((binding ...)
            (value ...)
            ...)
  single-child-template)
```

当前版本只接受至少一个 identifier binding、至少一行固定 datum table 和一个 child template。每个 row 的 value 数量必须与 binding 数相等；否则 macro expansion 报错。模板中的同名 symbol 被 row datum 替换，再以原调用位置的 syntax context 重新送入 `parse-node`。

```racket
(row #:id cpu-metrics #:gap 8
  (repeat/ui ((card state label)
              (core-0 core0 "CORE A")
              (core-1 core1 "CORE B")
              (core-2 core2 "CORE C")
              (core-3 core3 "CORE D"))
    (metric-card #:id card #:label label
                 #:dynamic state #:max-chars 3 #:gap 4 #:padding 6)))
```

该表在 compile time 生成四个 `metric-card` calls；每个 card 随后内联为 `column + static text + dynamic text-run`。最终 runtime Scene 没有 `repeat/ui` tag、列表值、template closure、循环索引或 key。

## 2. 内联与稳定命名

| 表行 | 组件调用 | 最终基础 IDs |
|---|---|---|
| `(core-0 core0 "CORE A")` | `metric-card #:id core-0 ...` | `core-0`、`core-0$label`、`core-0$value` |
| `(core-1 core1 "CORE B")` | `metric-card #:id core-1 ...` | `core-1`、`core-1$label`、`core-1$value` |
| `(core-2 core2 "CORE C")` | `metric-card #:id core-2 ...` | `core-2`、`core-2$label`、`core-2$value` |
| `(core-3 core3 "CORE D")` | `metric-card #:id core-3 ...` | `core-3`、`core-3$label`、`core-3$value` |

因为 expanded forms 回到 `register-id`，row table 中重复的 component IDs 或与外层 tree 冲突的 ID 都会触发既有 compile-time duplicate error。`repeat/ui` 不需要自己的 runtime key namespace。

## 3. 与 GPU 编译路径的关系

四卡 CPU showcase 的 compiler output 包含 4 个 dynamic text nodes、12 个 dynamic glyph cells 和总计 59 个 glyph cells。每个 card 的静态 label 使用 page-1 ASCII atlas，动态数值使用 page-0、长度为 3 的 fixed glyph slot。`refresh-core0` action 只更新 `core-0$value` 的三个固定 glyph IDs。

| 编译产物 | `repeat/ui` 的结果 |
|---|---|
| Layout Plan | 固定的 4 个 card columns、8 个 label/value text nodes |
| Glyph placement | 4 个独立 dynamic run，各自已有固定 cell/placement range |
| Event Map | `refresh-core0-button` 是普通 base button，固定 hit rect |
| Coalesced Batch | `coalesced-activate-refresh-core0-button` 仍使用 winner-only release/action writes |
| Tile plan | action 只使用 compiler-selected tile mask；无 list damage traversal |

同时，Render Schedule 的动态 geometry damage 已从固定 `throughput` ID 改为遍历 `c-action-plan-instance-updates` 的实际 layout binding。这使任意 component/repeater 生成的 progress ID 都可进入同一 Damage/Tile lowering。

## 4. 验证

`tests/run.rkt` 现在验证：repeat Scene 有 4 个 dynamic nodes、glyph capacity 为 59、四组 derived IDs、四组各 3 glyph placement state，以及 `refresh-core0` action 的 GPU update 只指向 `core-0$value`。

`tools/verify_repeat_dashboard.sh` 执行可复现的真实验证：导出 showcase Scene，断言 `repeat/ui` 未进入 JSON，启动 Xvfb + Vulkan/llvmpipe wgpu Surface，在 Event Map 固定 rect `(120,220)` 进行 X11 click，并核对：

```text
coalesced-activate-refresh-core0-button
glyph-id-patch core-0$value: [928..932), [960..964), [992..996) (12 bytes)
```

因此 repeated component 不仅停留在宏展开输出，而是进入真实 text glyph patch、tile scheduling 与 GPU draw 路径。

## 5. 限制

当前 `repeat/ui` 接受 raw fixed datum table，不接受 runtime collection、runtime filtering、unbounded range、computed component count 或 React-style keys。这是设计约束：使用者可写静态 monitor rows、固定 action palette、编译期已知 channel strip 或 settings fields；而任何会令 node count、glyph capacity、state dependency 或 event geometry 在运行时变化的集合，必须由新的显式 bounded abstraction 处理，而不是隐式引入 diff engine。 
