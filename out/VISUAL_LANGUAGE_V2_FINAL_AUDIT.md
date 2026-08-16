# Noir Visual Language v2 — 最终对照审查

## 审查对象

- `log-browser-visual-v1-v2-comparison.png`
- `realtime-monitor-visual-v1-v2-comparison.png`
- 两侧均来自同一 1280×720 X11/Vulkan 宿主路径；列表容量、action ID 与冻结交互ABI保持不变。

## 已确认的视觉提升

视觉v1只有标题条、列头、四行正文和底部操作条，所有内容堆叠在画面上部；正文、详情与操作缺少独立surface，状态色覆盖面积过大，动态详情初始字形还会形成噪声。视觉v2将同一应用重组为稳定的桌面信息架构：左侧品牌rail、page header、四个summary tiles、独立table card、独立context card和右下主操作。信息层次可以在一眼内被识别，不再依赖颜色条区分区域。

两套应用共享同一个几何节奏：workspace从`x=236`开始；summary tiles位于`y=140`；table card位于`236,228,996×300`；4×32列表viewport位于`236,312,996×128`；detail card位于`236,544,996×128`。日志和监控因内容不同而保持各自语义，但视觉骨架、padding、标题层级、表格band和操作位置完全一致。

字体层级已经可见：品牌、page title、eyebrow、metric label/value、table title/meta、column header、page-3 tabular rows与footnote不再使用同一尺寸。正文采用10px固定advance与16px字形高度，行扫描密度显著提升；page-2静态chrome仍保留灰度比例字形。

颜色从大面积中灰和高亮整行填充转为Neutral Ink深色基底、低对比surface阶梯、单侧accent与有限状态tint。监控表中的WARN/ERROR仍可辨识，但不再压过数据文本；日志应用不会因状态色破坏主层级。

## 编译型约束审查

结构oracle确认两个Scene均只包含`stack`、`overlay`、`text`、`button`、`row`、`virtual-list`、`scrollbar`与`scrollbar-thumb`基础tag，高层`workspace-shell`、`page-header`、`metric-tile`与`action-button`全部在宏展开期消失。两个Scene均无canvas越界；日志字形page分布为page1=29、page2=281、page3=128，监控为page1=29、page2=310、page3=144。

视觉提升没有引入运行时theme查找、组件树、动态reflow、字体测量或任意样式对象。新的font scale、text inset、固定坐标和组件variant均被折叠进现有layout/glyph/quad产物。

## 明确保留的边界

视觉v2接近EUI-NEO的**层次、密度和组件节奏**，但不是像素级复刻。当前Noir仍缺少图标资产、真实圆角/模糊阴影、细粒度hover/pressed组件变体、非全大写排版策略和更丰富的数据可视化；四行viewport也是性能fixture的刻意限制。上述能力应继续以有限静态资产或固定状态patch引入，不能重新建立运行时样式系统。

## 最终判断

视觉v2已从“验证渲染路径的工程界面”提升为具有一致品牌、桌面信息架构和可读数据层级的设计系统基线。它达到本阶段交付标准，同时保留了Noir的AOT数据流与严格proof边界。
