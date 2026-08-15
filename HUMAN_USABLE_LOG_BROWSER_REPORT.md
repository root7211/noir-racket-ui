# 人类可用日志浏览器修复报告

**作者：Manus AI**  
**范围：Noir `examples/log-browser.rkt`，Rust/wgpu 30 宿主与真实 X11/Vulkan 验收**

## 摘要

本轮工作将日志浏览器从“状态与渲染路径正确、但视觉不可用”的验证样例修复为一个可阅读、可操作的紧凑像素界面。修复没有改变已冻结的 `virtual_list_plan`、`row_activation_plan`、`scrollbar_plan` 或 `list_navigation_plan` 字段语义；新增或变更的内容限定在全局字体图集、静态布局颜色、glyph 直接提交条件和应用层示例布局。

最终界面保留 Noir 的固定容量与编译期几何原则：10,000 条逻辑日志继续映射至 4 个物理 GPU row slot；End、鼠标选择、Enter、tail append、滚动条和详情文字均沿原有 compiler-proved 数据流执行。最终真实截图见 `out/log-browser-ui/10-clean-detail.png`。

## 修复的问题与处理方式

| 问题 | 根因 | 修复 | 保持的不变量 |
|---|---|---|---|
| 字体上下颠倒 | placement shader 的atlas V坐标与上传纹理行方向相反 | `host_placement.wgsl` 与legacy `host_text.wgsl` 仅翻转V采样 | glyph placement位置、slot和Scene ABI不变 |
| 右侧标题/文本被裁剪 | text run增加12%左边距后，仍以100%宽度分配glyph advance | Racket lowering预留左右inset，只在76%可用宽度内分配固定glyph cell | 所有NDC位置仍在编译期固定 |
| 3×5字形难以阅读 | 低分辨率图集使长文本与细节字母歧义过强 | 维持每页6×8 atlas cell和地址ABI，替换为5×7数字/大写字母位图并同步UV | atlas page、glyph ID和运行时写入范围不变 |
| 白色横条覆盖日志状态 | 未指定背景的text节点仍生成不透明浅色quad | 默认text quad变透明；显式`#:background`仍编译为固定深色表面 | glyph仍由独立placement pipeline绘制 |
| 详情写入但不可见 | `no-packets`请求跳过activity compute后，局部tile仍读取旧的零activity indirect命令 | no-packets局部tile直接绘制已证明placement range；无compute dispatch | tile、placement范围和no-packets worklist均不扩大 |
| 详情文字叠加乱码 | 隐藏动态计数器与detail使用同一stack，glyph pipeline不消费该quad透明度 | 删除重叠计数器，只保留29个已证明detail glyph cell | Action Slot与details的固定tile保持不变 |

## 用户可见界面

日志浏览器由深色应用栏、列头、三行紧凑log viewport、右侧scrollbar、详情面板及底部固定append操作区组成。文本使用近白5×7像素字，`WARN`、`ERROR`、`DEBUG` 为低饱和深色row surface；hover与selected为更高亮但不刺目的独立蓝色层级。行文本默认不再以不透明quad覆盖这些状态色。

> 终态截图验证可读文本包括 `SYSTEM LOG BROWSER`、`LEVEL TIME SOURCE MESSAGE`、`DETAIL ERROR SELECTED` 和 `APPEND FIXED TAIL`。这说明标题、列头、详情与操作语义均由实际GPU glyph路径呈现，而非测试日志替代。

## 真实X11/Vulkan工作流

| 顺序 | 真实输入或生产入口 | 观察到的固定路径 |
|---:|---|---|
| 1 | `--inject-log-append system-log-browser` | 3个tail record写入9997–9999；初始viewport下为`visible=0`、`arena-only=3`、glyph GPU写入为0 |
| 2 | X11 `End` | viewport变为9997；4-slot ring为`[1,2,3]`；只提交可见row subrange与no-packets worklist |
| 3 | X11鼠标释放第二个tail row | 选择逻辑行9998、物理slot 2；`ERROR`有限palette写入预证明row颜色地址 |
| 4 | X11 `Enter` | 调用`coalesced-activate-append-tail`；详情写入29个固定glyph cell |
| 5 | 局部tile呈现 | `tile=0`的详情packet以`reason=no-packets-direct`直接提交；没有packet activity compute upload或全屏重绘 |

## 回归结果

下列最终验证全部返回成功：Racket全量回归、冻结ABI篡改拒绝、scrollbar真实X11拖动、PageUp/PageDown/Home/End导航、row activation，以及日志浏览器的tail append→End→ERROR selection→Enter详情→篡改拒绝回归。

| 回归 | 最终状态 |
|---|---|
| `tests/run.rkt` | 通过 |
| `tools/verify_frozen_list_abi.sh` | 通过 |
| `tools/verify_scrollbar_plan.sh` | 通过 |
| `tools/verify_list_navigation_plan.sh` | 通过 |
| `tools/verify_row_activation.sh` | 通过 |
| `tools/verify_log_browser.sh` | 通过 |

## 当前边界与后续建议

这是可用的像素风日志浏览器MVP，不是完整IDE日志视图。列宽仍为编译期固定monospace geometry，不能拖拽；level仍以固定row surface表示；还没有搜索、过滤、时间格式化或可变宽unicode shaping。这些都应作为新的应用层计划或更高版本字体资源工作处理，而不应回写或改变已冻结的长列表ABI。

下一步建议是用同一组冻结列表原语实现**实时监控表格**，测试周期性指标更新、选中详情和多列数值变化能否同样保持可读且局部更新。
