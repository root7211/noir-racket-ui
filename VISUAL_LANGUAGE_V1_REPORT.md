# Noir 编译期桌面视觉语言 v1 交付报告

**作者：Manus AI**
**状态：已实现并完成真实 X11/Vulkan 回归**

## 1. 交付结论

Noir 现在拥有一套真正进入编译产物的**桌面视觉语言 v1**。它不是运行时主题引擎，也不是组件树上的样式查找层；语义色彩、surface层级、分隔线、状态tint、密度与desktop-wide画布均在Racket宏展开期确定，并lower为既有quad、glyph placement、tile与worklist数据。

本阶段最重要的修复是建立了独立的 `visual_language_plan v1`。此前即使Racket以1280×720计算desktop-wide几何，Rust宿主仍以640×360创建窗口和offscreen canvas，导致真实画面被缩放和裁剪。现在Scene显式携带preset及固定canvas，Rust在创建窗口前验证并使用该产物；无法从layout或窗口尺寸猜测视觉尺度。

| 维度 | v1实现 |
|---|---|
| 视觉画布 | `bench` 固定为640×360；`desktop-wide` 固定为1280×720、32px margin |
| Scene ABI | `noir-visual-language-plan-v1@1`，含schema、revision、preset、width、height、margin |
| 色彩层级 | canvas、quiet canvas、surface、raised surface、overlay、subtle/strong border、primary/muted/inverse text、accent与语义状态色 |
| 静态装饰 | `surface` elevation border、toolbar/table-header/detail-panel divider、status indicator均lower为固定overlay quad |
| 状态语义 | 行级WARN/ERROR/DEBUG继续使用原固定颜色offset，但改为低压tint，避免密集表格成为高饱和色块 |
| 字体策略 | page 2比例字体用于标题、列头与静态chrome；固定容量列表正文继续走page 0/1 legacy热路径 |
| 运行时路径 | 无运行时theme查询、无样式对象、无layout reflow、无组件tag泄漏 |

## 2. 视觉语言的编译模型

视觉语言的核心不是给Scene添加一个可选元数据字段，而是让同一静态canvas成为下列编译pass的唯一几何真值：root frame、layout NDC、glyph packet bounds、tile culling、damage、event NDC、virtual-list scroll scissor、scrollbar thumb与字体placement。

> `visual-preset → semantic token expansion → fixed canvas/layout/NDC → glyph/tile/worklist plan → visual_language_plan proof → matched host window + offscreen canvas`

Rust启动期执行三层准入。第一层检查 `abi_contracts.visual_language_plan`；第二层检查payload schema和revision；第三层对preset作封闭匹配，并验证每个layout条目的NDC反算rect均包含在compiler-owned canvas中。因而宿主无法接收名称正确但尺寸被篡改的desktop-wide Scene。

## 3. 两个应用的迁移

日志浏览器和实时监控表格均已声明 `(visual-preset desktop-wide)`，并采用完整语义token表。两者使用相同的组件变体：raised toolbar、弱分隔table header、带border的列表surface、raised detail panel、低饱和accent status pill。应用层的列表容量、row template、data-register、detail glyph地址、row activation、scrollbar、navigation和font asset契约均保持原有ABI。

| 应用 | 视觉重点 | 保持不变的执行语义 |
|---|---|---|
| 系统日志浏览器 | 冷色层级、弱元数据header、低压append action | End、row 9998选择、detail更新、Enter activation、tail arena-only更新 |
| 实时监控表格 | 深青surface、青绿色action、黄色WARN与红粉ERROR低压tint | 10,000行容量、可见性分流、数值glyph patch、详情联动、固定refresh batch |

真实帧见：

- [`out/log-browser-visual-language-v1.png`](out/log-browser-visual-language-v1.png)
- [`out/realtime-monitor-visual-language-v1.png`](out/realtime-monitor-visual-language-v1.png)

## 4. 验证证据

`./tools/verify_visual_language.sh` 已通过。它首先运行Racket语言回归，使用Rust 1.87/wgpu 30构建宿主，再导出两个desktop-wide Scene。`tools/audit_visual_canvas.py` 对两个Scene执行NDC反算审计，结果均为 `violation_count: 0`。

脚本还生成三类结构化攻击样本：错误visual plan schema、未准入preset、以及1280→1279的canvas width篡改。三者均在首帧前拒绝。随后脚本串行执行font placement、日志浏览器和实时监控表格的真实X11/Vulkan回归。

| Oracle | 结果 |
|---|---|
| 双Scene canvas containment | PASS；各自0项layout越界 |
| `visual_language_plan` schema篡改 | 首帧前拒绝 |
| 未准入preset篡改 | 首帧前拒绝 |
| desktop-wide width篡改 | 首帧前拒绝 |
| page 2 font asset/placement proof | PASS |
| 日志浏览器End→row→Enter | PASS |
| 监控可见/不可见刷新分流 | PASS；纯不可见更新保持0 glyph GPU写入与0 render request |
| 真实X11/Vulkan截图 | PASS；窗口与offscreen canvas均为1280×720 |

## 5. 保留边界

v1显著改善了桌面chrome、空间层级和状态信息组织，但高密度列表正文仍采用既有5×7 legacy glyph atlas。其原因是这是受冻结的列表热路径：动态行glyph仅更新固定cell地址，页面0/1采样与row recycling均已经过真实交互回归。视觉语言没有为了外观而把这一热路径替换为运行时字体查询。

因此，下一阶段的视觉质量工作应是**比例字体的动态高密度文本路径**：在不破坏fixed data-register地址的前提下，为page 0/1行正文引入经proof的MSDF或灰度比例atlas cell编码。它应被视为字体渲染能力演进，而不是回退到运行时样式或layout系统。

## 6. 可复现入口

```bash
cd /home/ubuntu/noir_review/noir-racket-ui-statistical-analysis
./tools/verify_visual_language.sh
```

该入口会清理篡改Scene和Xvfb进程，不依赖手工显示器尺寸，也不会把视觉canvas配置藏在环境变量或shell参数中。
