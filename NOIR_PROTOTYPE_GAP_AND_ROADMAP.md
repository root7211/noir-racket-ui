# Noir 原型缺口盘点与下一阶段技术演进路线

## 结论

Noir 已经跨过“静态GPU UI实验”的门槛，进入 **受限闭合域的编译型桌面工作台原型** 阶段。当前系统能够在编译期固定Scene、组件几何、字体资源、tile、状态槽、两个数据arena、modal焦点视觉与一条跨视图业务事务，并在Rust宿主中将其验证为有限GPU写集。

当前最重要的缺口不是再增加一个孤立组件，也不是恢复性能测试，而是把已有的跨视图确认事务扩展为**可持久、可见、可组合但仍固定容量的领域状态**。否则Noir虽能证明“发生了一次事务”，却尚不能证明“事务如何改变一个持续存在的数据模型，并在滚动、视图切换和后续动作中保持一致”。

> Noir 的路线不应模仿通用保留模式GUI的无限动态能力；应把现实桌面应用中高频、可界定、容量可预先声明的交互域逐步编译为可证明的有限状态机。

## 当前稳定能力

| 领域 | 当前已验证能力 | 稳定边界 |
|---|---|---|
| 编译器与Scene | `#lang noir/ui` 宏、静态布局、状态槽、action slot、glyph、tile和ABI导出 | 组件与状态集合必须在编译期闭合。 |
| 视觉语言 | Material token、正常大小写字体、圆角SDF、AA、阴影、icon、rail、dialog/menu和受限动效 | 资源和绘制范围为预分配资产。 |
| 数据视图 | Systems `10,000 × 4`、Alerts `2,048 × 3`、固定物理槽、滚动、选择、detail、scrollbar | arena数、容量、列模板和视图owner均冻结。 |
| 焦点与overlay | modal状态、Tab/Shift+Tab、Escape、focus-ring独立GPU pass | 仅覆盖预声明modal焦点子图。 |
| 跨视图事务 | Alerts确认到Overview计数：1 state、1 color lane、29 detail glyph、8 count glyph、tile `0x1` | 仅一条canonical action，且写集不可扩张。 |
| 可信验证 | ABI gate、启动期proof、篡改拒绝、Racket回归、真实X11/Vulkan和截图 | 当前覆盖的是已实现的受限路径，不是任意程序的形式化验证。 |

## 仍缺失的核心特性

### 1. 持久领域状态与可见状态演化

当前Alerts确认事务只增加Overview计数，并临时保持选中行的颜色；它没有将“该逻辑告警已确认”存入一个随滚动和视图切换持续存在的固定数据状态。因此，重新滚动回同一逻辑行时，系统尚无已证明的机制恢复其确认样式、状态glyph或可操作性。

缺失的不是一个泛化数据库，而是一个**固定容量的领域状态表**：以逻辑行索引为地址、以编译器限制的枚举值为内容、以预计算逻辑行到物理槽映射为可见性桥梁。

### 2. 多事务组合与冲突语义

当前有一条跨视图事务，但没有多个领域事务之间的编译期组合规则。框架需要能够表达例如确认、取消确认、静音、批量确认等有限动作，并在编译期证明它们的状态槽、资源地址和tile范围是否可交换、是否冲突、是否可以批融合。

这并不意味着引入任意运行时事务系统；目标是让编译器从一组有限、带类型的事务模板生成冲突图、winner write及合法批次。

### 3. 焦点作用域、键盘可用性与静态无障碍语义

Noir 已有modal Tab环和列表键盘导航，但尚没有跨rail view的焦点恢复、view-local focus scope、默认焦点、快捷键冲突证明，亦没有导出的静态role/label/shortcut语义。它能演示键盘路径，但还不能作为严肃桌面工具的键盘优先界面。

应把无障碍能力限定为编译期静态语义表，而非运行时扫描组件树：每个静态节点可导出role、label、状态描述、快捷键和focus owner；宿主只消费已证明数组。

### 4. 受限表单、编辑与验证

已有固定容量ASCII输入、键盘转换表和命令映射，但它们尚未被整合为完整表单能力：字段级错误、提交/取消、跨字段约束、dirty状态与确定的焦点跳转。对工作台类应用而言，受限表单比新增通用组件更接近真实使用。

### 5. 外部数据进入、持久化与失败处理

两个arena当前是编译产物和固定批更新的消费端，尚没有受限文件导入、socket/IPC输入、缓存、持久化或错误恢复模型。若直接接入自由异步I/O，会破坏Noir最有价值的可证明边界。

正确的缺口定义是**bounded data source**：固定记录格式、固定批大小、固定队列槽、固定背压、固定失败状态和固定可见更新路径。I/O只负责填入边界缓冲；界面仍只消费已证明的批次。

### 6. 可重用组件族与应用级组合

当前组件宏与workbench足以说明方法，但缺少小而完整的受限组件族及其组合契约，例如状态badge、toolbar、filter chip、empty/error/loading surface、确认条、只读metric与可编辑setting row。缺失的不是“无限组件生态”，而是能支持多个研究/运维应用的稳定语言标准库。

### 7. 视觉质量的系统化收敛

Material token、fontc和SDF视觉路径已经存在，但仍缺少统一的视觉回归基线：状态色、disabled/selected/acknowledged层级、数字字形可读性、紧凑表格排版、空态和错误态，以及截图差异oracle。视觉风格不能继续依靠fixture逐项补丁。

### 8. 宿主平台与应用生命周期

当前宿主刻意使用X11与固定画布，尚缺离散窗口尺寸档位、DPI缩放、clipboard、文件选择、拖放、最小化恢复、应用状态恢复与可发布打包。用户明确不依赖Wayland，因此近期不应把Wayland作为主线；X11与XWayland兼容、固定canvas bucket和Linux桌面生命周期更符合当前边界。

### 9. 工具链、诊断与可复现实验体验

项目仍像研究代码库：需要明确的`noirc`入口、manifest、ABI版本迁移策略、错误信息定位、headless test runner、示例模板和应用构建输出。对开源研究社区而言，这比立即追求生态规模更有价值。

## 演进原则

每一个新能力必须先回答五个问题：其容量上限是什么；状态空间如何枚举；GPU/CPU写入地址如何在编译期列出；哪些事件能触发它；失败或越界时是否能证明零写入。无法回答这些问题的需求，不应直接进入Noir主线。

| 应坚持的约束 | 应避免的偏航 |
|---|---|
| 固定容量、离散端点、显式ABI、启动期反向proof、局部tile写集 | 任意组件查询、反射式状态树、无限动态布局、隐式diff、运行时资源搜索。 |
| 用新受限计划扩展能力 | 将一个fixture特例偷渡为未定义的通用运行时。 |
| 用真实输入和篡改拒绝验证每条新路径 | 只以Scene JSON或截图宣称能力完成。 |
| 分离领域I/O边界和GUI写集 | 让异步I/O直接改变GPU资源或UI树。 |

## 推荐技术路线

### 阶段 A：`acknowledged_row_state_plan v1` — 下一项应立即实施

这是最小且最关键的下一步。为Alerts的2,048个逻辑记录建立固定容量`open | acknowledged`状态表，并预分配每个物理行的状态glyph/颜色端点。现有确认事务将从“计数加一”升级为：写入选中逻辑行的确认位、更新当前物理行、更新Overview计数；滚动recycle时，已证明的逻辑行状态重新lower到当前物理槽。

| 编译期产物 | 运行时固定路径 | 必须证明 |
|---|---|---|
| 逻辑状态表容量、两种枚举值、每物理行状态glyph槽、状态色、tile集合 | 一个逻辑行状态写入；当前物理lane的颜色/glyph patch；Overview计数patch | 逻辑索引在Alerts容量内；逻辑→物理映射正确；状态glyph、颜色、计数和tile均无跨arena别名。 |

该阶段会使Noir首次拥有可滚动、可持久、可视化的领域状态，而不引入通用数据绑定框架。

### 阶段 B：`bounded_transaction_family_plan v1`

在确认状态稳定后，把确认、取消确认和批量确认收敛为有限动作族。每个动作必须声明输入状态、输出状态、可写状态表、instance/glyph范围及tile并集。编译器生成冲突图和批融合准入；宿主只执行winner writes和合并后的固定RenderRequest。

先限制为Alerts单arena与Overview汇总端点，不要立即允许任意数据arena之间互相写入。

### 阶段 C：`focus_scope_accessibility_plan v1`

为rail三视图、Alerts列表、detail、Acknowledge和overlay建立静态focus scope。它应提供view切换焦点恢复、每view默认焦点、快捷键表、role/label/state描述导出和冲突拒绝。此阶段将Noir从“可注入键盘测试”提升为“可键盘使用的工作台”。

### 阶段 D：`bounded_form_plan v1`

在Settings或部署dialog中实现小型受限表单：固定字段、固定ASCII/数值域、固定错误glyph端点、固定提交/取消动作和跨字段验证表。目标是证明Noir既能处理可视化数据，也能处理真实配置工作流。

### 阶段 E：`bounded_data_source_plan v1`

定义可选的数据输入边界，而非直接引入自由异步架构。推荐顺序是：文件导入或本地IPC → 固定记录解码 → 固定批队列 → 已证明`data_update_batch` → 局部列表更新。每个源必须有上限、背压、错误状态和可重复回放日志。

### 阶段 F：视觉与开发者体验收敛

将状态视觉、字体、空态/错误态、密集表格和截图oracle集中为一套visual regression规范；同时提供`noirc build`、headless验证、ABI迁移检查和最小应用模板。至此Noir应形成可由外部研究者克隆、运行、修改并复验的研究框架。

### 阶段 G：Linux桌面产品化边界

最后再处理离散canvas resize bucket、DPI、clipboard、文件选择、状态恢复和打包。它们应被设计为宿主能力manifest，而不是绕过Scene proof的任意回调。Wayland仍可保持非目标；X11/XWayland路径足以支撑当前研究与Linux原型发布。

## 依赖图与优先级

```text
acknowledged_row_state_plan
        ↓
bounded_transaction_family_plan
        ↓
focus_scope_accessibility_plan ──→ bounded_form_plan
        ↓                              ↓
visual_regression + component family   bounded_data_source_plan
        ↓                              ↓
             host lifecycle + noirc tooling
```

| 优先级 | 计划 | 原因 | 是否应立即做 |
|---:|---|---|---|
| P0 | `acknowledged_row_state_plan v1` | 为现有跨视图事务补齐持久可见语义，是当前最短价值闭环。 | **是** |
| P1 | `bounded_transaction_family_plan v1` | 验证多个固定事务能组合而不失去proof边界。 | 在P0完成后。 |
| P1 | `focus_scope_accessibility_plan v1` | 让已有工作台真正可键盘使用并提升研究可用性。 | 可与P1交替。 |
| P2 | `bounded_form_plan v1` | 覆盖配置型桌面应用，而非只做数据浏览。 | P1稳定后。 |
| P2 | `bounded_data_source_plan v1` | 让应用接受外部真实数据，但必须先拥有稳定状态语义。 | P2后半段。 |
| P3 | 工具链、visual regression、host lifecycle | 提升外部可复验性与可发布性。 | 与P1–P2持续建设。 |

## 明确不建议的下一步

当前不建议优先实现第三个数据arena、任意嵌套视图、通用Redux式状态树、自由异步任务模型、无限列表、跨平台宿主重写或新一轮性能矩阵。这些工作要么绕过当前唯一的差异化优势，要么在缺少持久领域状态、动作组合规则和开发工具前放大复杂度。

**推荐的下一条提交主线是：`acknowledged_row_state_plan v1`。** 它以当前已证明的Alerts确认事务为输入，把“确认”变成可滚动恢复、可视觉辨识、可反向验证的固定领域状态，同时保持Noir最重要的哲学：运行时只选择编译器已经列出的最短路径。
