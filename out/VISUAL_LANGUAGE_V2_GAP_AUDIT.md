# Noir视觉语言v2差距审计

## 真实截图结论

| 当前问题 | 日志浏览器/监控表格中的表现 | v2目标 |
|---|---|---|
| 信息架构过平 | 标题、列头、列表、按钮全部是一条条横向色带 | 建立应用header、指标/状态条、主数据card、右侧detail card、底部action/status区 |
| 画布利用率低 | 上方约260px有内容，余下大面积无语义空白 | 使用两栏主frame和固定高度数据surface填充可用区域 |
| 表格缺少列系统 | 文字依靠空格排列，列头与正文没有明确对齐、separator或padding | 固定列起点、列宽、row padding和弱竖向分隔；保持编译期cell地址 |
| 动态detail发生视觉碰撞 | 初始或更新后的详情字形挤入列表下缘，出现难读叠字 | 将detail放入独立surface与固定clip，不与row arena共享视觉区域 |
| 状态色面积与语义不平衡 | WARN/ERROR整行高饱和填充，压过文字与主accent | 使用窄状态rail、低alpha行tint和小型badge三层语义 |
| 标题缺少层级 | 主标题、列头、操作按钮字体尺度相近 | display标题、meta副标题、section label和data text形成4级排版 |
| 操作按钮像色带 | `APPEND FIXED TAIL` / `REFRESH FIXED BATCH`占满整行，无明显边界与状态 | 使用右上或footer中的compact filled/outline button，固定44px高度与12px radius |
| surface层级不够 | 背景、表头、列表与detail的明度接近 | 固定canvas/surface/raised/hover四级暗色值与1px边框 |
| 缺少品牌焦点 | 只有横向灰蓝色，没有明确accent节奏 | accent仅用于logo/active rail/focus/action，避免覆盖普通内容 |
| row密度不稳定 | 3条可见数据之后出现重叠/乱码样的动态detail视觉 | 将row height、baseline、clip与detail区域分开证明，目标28–32px稳定行高 |

## v2实现优先级

第一优先级不是阴影或动画，而是**应用骨架与信息分区**。Noir应先用已有stack/column/row/surface宏生成固定侧栏（或窄品牌rail）、header、主数据card和detail card；随后才增加button variant、badge、边框、圆角和状态rail。所有改造必须保持现有state slot、data-register glyph word、tile/worklist与事件地址可证明。
