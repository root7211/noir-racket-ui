# Fixed-Capacity Row Recycling 与数据绑定报告

**作者：Manus AI**  
**范围：** Noir `virtual-list` 的固定logical数据容量、physical GPU row ring、编译期glyph data-binding patch recipe，以及真实X11/Vulkan wraparound验证。

## 概要

本实现将列表的**逻辑数据容量**与**物理GPU row槽**分开。新DSL形式为：

```racket
(virtual-list #:id telemetry-ring
              #:logical-capacity 12
              #:physical-slots 4
              #:visible-rows 3
              #:row-height 28
              #:max-chars 10
  (data-table ((sample-aa "SAMPLE AA") ...))
  (row-template ((ring-a "SAMPLE AA") ...)))
```

`data-table`必须列出固定数量的literal logical数据；`row-template`必须列出固定数量的physical GPU槽。两者均在Racket宏展开时完成检查。运行时不拥有动态数据模型、行树、键查找或文本shape器；它只选择一条compiler-emitted transition并写入该transition中固定的buffer地址。

## 编译期ABI

| Artifact | telemetry-ring值 | 含义 |
|---|---:|---|
| logical capacity | 12 | 固定logical数据行上限 |
| physical slots | 4 | 唯一实体化的quad/glyph row-template数量 |
| visible rows | 3 | viewport渲染行数 |
| logical data table | 12个uppercase ASCII标签 | 进入slot的预shape glyph资源源 |
| directed transitions | 18 | `2 × (12 - 3)`相邻viewport边 |
| quad Y patch/edge | 8 | 4个physical槽 × 2个quad |
| glyph Y patch/edge | 36 | 4个physical槽 × 9个glyph placement |
| glyph-ID patch/edge | 36 | 每个physical glyph cell的固定logical数据绑定 |
| viewport draw | 3 range / 6quad / 3range / 27glyph | 仅目标viewport物理slot |

对目标logical viewport `t` 和physical slot `p`，compiler固定其logical所有者为：

> `logical = t + ((p - t) mod physical_slots)`

当该值超过logical capacity时，compiler将该physical槽的glyph ID recipe固定为空格glyph、位置固定到hidden NDC；末端viewport不会访问不存在的logical数据。该条件不是运行时分支的来源，而是每条末端transition已经写入Scene的具体patch值。

## Host反向Proof

Rust在创建窗口前验证logical capacity、physical slot数和initial ring为canonical；检查每条边严格相邻；重建目标viewport的physical row tile序列；验证4个physical槽的全部instance/glyph position patch地址；从固定logical label重新shape uppercase ASCII glyph ID并逐项比对36项compiler glyph-ID patch。

篡改第一条边的glyph ID后，host在创建窗口前拒绝Scene：

> `recycling list telemetry-ring scroll edge 0 -> 1 has invalid glyph data-binding patch proof`

因此，runtime不可能利用错误或扩张的绑定表把未证明的数据写入GlyphCell arena。

## 真实X11/Vulkan验证

真实X11 wheel-down输入跨越多个ring wrap。`3 → 4`的目标viewport通过physical slot边界，compiler选择row tiles `[0,1,2]`；host记录8项quad位置patch、36项glyph位置patch与36项glyph-ID data binding patch。render pass继续使用viewport-only row subranges：3个quad DrawRange、6个quad实例、3个glyph subrange与27个glyph placement，packet activity为`no-packets`。

```text
virtual-list scroll: list=telemetry-ring from=3 to=4 row-tiles=[0, 1, 2]
instance-patches=8 glyph-patches=36 glyph-id-patches=36 recycling=true
virtual-list scroll-submit: list=telemetry-ring viewport=4
quad-ranges=3 quad-instances=6 glyph-subranges=3 glyph-placements=27
worklist=no-packets
```

Racket全量回归、Rust release build、真实X11/Vulkan ring wrap与tampered glyph binding rejection均通过。

## 边界

该阶段提供的是**固定逻辑数据表的可扩展绑定模型**，不是任意运行时数据源：新的逻辑值仍必须通过预分配的固定容量register或专用data patch ABI写入。logical容量可增大而physicalGPU资源保持由`physical-slots`限定；然而当前fixture使用12条literal数据来验证正确性，尚未对10,000条数据进行编译/内存/滚动基准。

下一步应增加`data-register-table`：为固定上限的logical行分配紧凑CPU侧数据arena与固定文本patch recipe，再基于同一4/26 physical slot ring在1,000和10,000逻辑行上测量滚动、单行更新和批量更新。
