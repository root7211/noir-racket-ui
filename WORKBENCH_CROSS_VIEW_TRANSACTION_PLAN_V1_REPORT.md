# Workbench Cross-View Transaction Plan v1 — Fixed Executor Report

## 交付结论

`workbench_cross_view_transaction_plan v1` 已从 Racket 编译期写集产物升级为可执行的受限跨视图事务。唯一允许的路径是 Alerts 数据视图中已选择的行触发 `workbench-acknowledge-alert`，将 `workbench-alert-ack-count` 增加一，并同步更新 Alerts 物理行颜色、Alerts detail text 与 Overview 的固定八字符计数端点。

该实现不引入通用事务调度器、组件搜索、运行时布局、动态写集或性能采样。Rust 宿主在启动期将Scene计划压缩为一个仅包含已证明索引、地址和tile掩码的运行时结构；事件期不读取节点树或JSON map。

| 范围 | 冻结值 | 事件期行为 |
|---|---:|---|
| Source arena | Alerts `2048 × 3` | 仅读取已选择逻辑行，并以 `% 3` 选择唯一物理lane。 |
| State | `workbench-alert-ack-count += 1` | 一次有界整数加法；溢出拒绝且零写入。 |
| Row color | 3条已证明color lane | 只写当前物理lane的selected色。 |
| Alerts detail | 29个已证明glyph cell | 仅重写预分配detail文本。 |
| Overview count | 8个已证明glyph cell | 仅重写零填充十进制计数。 |
| Rendering | tile mask `0x1`，`no-packets` | 不构建worklist、不执行组件遍历或全帧逻辑推导。 |

## 执行器结构

启动期ABI gate先拒绝错误schema/revision、required标志和object-or-false形态；关联proof随后验证Alerts source、Overview target、唯一action/event、state、3条颜色lane、29个detail glyph、8个count glyph和tile并集。通过后，`CompiledWorkbenchCrossViewTransactionPlan` 保存以下闭合信息：action/event/state索引、Alerts list/view索引、物理槽数、selected色、两个glyph地址数组及固定tile mask。

> Commit前的所有可失败条件均被检查：source view必须激活、Alerts必须有选择、计数加法不能溢出、8个数字glyph必须可表示目标值、并且选中行必须拥有已编译日志等级。任一条件失败时，事务被消费但报告 `state-writes=0 gpu-writes=0`。

合法提交按固定顺序写入一枚state slot、一条instance color lane、29个Alerts detail glyph和8个Overview count glyph；随后仅排入 `RenderRequest::no_packets(0x1)`。Acknowledge按钮事件和Alerts行激活都在通用coalesced batch之前被截获，防止同一canonical action产生第二次非事务写入。

## 真实验证

回归脚本 `tools/verify_workbench_cross_view_transaction_executor_v1.sh` 已通过。它先运行四类Scene攻击拒绝，再在真实X11/Vulkan窗口中完成以下路径：进入Alerts、无选中点击Acknowledge、选择首行并确认、切回Overview、在保留Alerts选择的情况下按Enter。

| 路径 | 预期 | 已验证日志/证据 |
|---|---|---|
| Alerts无选中→Acknowledge | 零状态与GPU写入 | `reason=no-alert-selection state-writes=0 gpu-writes=0`。 |
| Alerts选中首行→确认 | 单次固定事务 | `state=0=>1`、1条颜色lane、29个detail glyph、8个count glyph、tile `0x1`。 |
| 切至Overview | 目标端点可见 | `02-overview-count-after-ack.png` 显示 `00000001`。 |
| Overview→Enter | 不得重复事务 | Alerts列表被owner-view门禁拒绝；成功事务日志只出现一次。 |
| 非canonical Scene | 启动期拒绝 | ABI、required禁用、action slot、target glyph四类攻击均被拒绝。 |
| rounded兼容 | 非workbench路径不受影响 | `ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS`。 |

视觉检查位于 `out/workbench-cross-view-transaction-evidence/`。Alerts截图显示选中蓝色行及预分配detail文本；Overview截图显示跨视图固定计数端点更新为 `00000001`。

## 非目标与后续边界

v1仍不支持任意跨视图动作、第二个事务、可变长度写集、动态数值宽度、第三数据arena、撤销/重做、持久化、异步I/O或性能基准。下一项合理扩展是为这条已完成的固定事务引入一个同样静态的“acknowledged”行状态，而不是扩展为通用状态管理器。

## 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui-statistical-analysis
bash tools/verify_workbench_cross_view_transaction_executor_v1.sh
```

成功标记为：

```text
WORKBENCH_CROSS_VIEW_TRANSACTION_EXECUTOR_V1_REGRESSION: PASS
```
