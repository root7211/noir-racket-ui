# Overlay State Plan v1 ABI

**状态：** 已实现并冻结为 `noir-overlay-state-plan-v1@1`。
**作者：** Manus AI。
**范围：** Noir 受限 Material dialog/menu 的预分配可见性状态转换。

## 1. 目标与非目标

`overlay_state_plan v1` 让已在宏展开期分配完成的 scrim、dialog、menu、按钮、文字、图标与阴影在有限的 **closed / open** 状态之间切换。它不创建或销毁节点，不重新计算几何，不查询主题，也不运行通用overlay管理器。运行时仅对编译器列出的 quad alpha、glyph alpha 与shadow alpha地址写入端点值，并提交一个已证明的局部tile范围。

| 包含 | 明确排除 |
|---|---|
| 二元 `0/1` 可见性状态 | 任意层数、任意状态机或运行时创建overlay |
| 预声明open与close action | 自由定位、锚点碰撞、重新layout与reflow |
| scrim、Escape、confirm/cancel、menu item关闭 | 通用事件传播或运行时focus路由 |
| 固定quad/glyph/shadow alpha patch | opacity动画、自由插值或动态文字资源 |
| 固定local tile mask与`no-packets` worklist | compute dispatch、动态packet发现或全屏猜测重绘 |

## 2. Scene 合同

顶层Scene必须显式携带以下字段：

```json
{
  "overlay_state_required": true,
  "overlay_state_plan": {
    "abi_schema": "noir-overlay-state-plan-v1",
    "abi_revision": 1,
    "entries": []
  }
}
```

`overlay_state_required` 只由成功lower的 `material-overlay-state` 宏导出。普通静态 `overlay` 原语保持 `false`，因此旧的tooltip、decorative overlay和bench Scene不会被错误升级为状态组件。若该标记为 `true` 而计划被篡改为 `false`，Rust宿主必须在GPU资源创建和事件循环之前拒绝Scene。

每个entry具有以下冻结字段。

| 字段 | 类型 | 含义与限制 |
|---|---|---|
| `id` | string | 唯一稳定overlay ID。 |
| `state` / `state_index` | string / u32 | 已有固定state slot；仅其值控制可见性。 |
| `initial_visible` | 0 或 1 | 必须与State Slot初始值严格一致。 |
| `open_action` | string | 唯一literal `set state 1` action。 |
| `close_actions` | string array | 非空、无重复；每项必须是literal `set state 0` action。 |
| `event_slots` | ascending u32 array | 仅允许触发open或close action的固定event地址。 |
| `instance_offsets` | ascending byte offsets | 44-byte `QuadInstance` 对齐的所有overlay quad alpha地址。 |
| `glyph_slots` | ascending u32 array | 48-byte `GlyphPlacementInstance` 的预分配alpha lane。 |
| `tile_ids` | u32 array | 该overlay转换唯一允许重绘的静态tile集合。 |

## 3. 编译期lowering

`material-overlay-state` 在Racket宏展开期完成下列工作：

1. 验证状态是固定0/1域，并将open/close action限定为唯一的literal `set` 写入。
2. 递归收集overlay子树的quad instance offset、static glyph slot与elevation shadow source；地址按ABI顺序排序并去重。
3. 将每个open/close action的damage并入同一预证明tile集合，使可见性转换不进入运行时相交测试。
4. 让scrim和menu的透明命中target、dialog确认/取消按钮和open按钮进入一个稳定event slot表。
5. 导出 `overlay_state_required=true`、v1计划以及已经存在的action、release-motion、rounded和shadow计划。

> **不变量：** 几何、字体、icon、圆角、shadow配方、tile、packet worklist与alpha地址都是Scene静态数据；运行时只选择`0`或`1`端点。

## 4. 宿主执行与绘制合同

Rust在启动期验证schema/revision、二元initial state、State Slot对应关系、open/close action的literal写集、event归属、quad offset对齐、glyph slot边界、shadow source映射和action tile范围。通过后，计划被压缩成无名称查找的索引表。

隐藏或显示一个overlay时，宿主同时执行以下固定操作。

| 资源 | 写入 |
|---|---|
| static quad instance buffer | 对`instance_offsets`的RGBA alpha lane写入保存的alpha或`0.0`。 |
| glyph placement buffer | 对`glyph_slots`的第48-byte实例末尾alpha lane写入`1.0`或`0.0`。 |
| immutable shadow instance buffer | 对由source instance反向确定的shadow layer alpha同步写入。 |
| RenderRequest | 合并entry唯一的tile mask，强制`no-packets`。 |

初始hidden状态在首次instance buffer上传后同步写入GPU buffer，避免CPU副本已隐藏而GPU初始帧仍残留surface的错误。

Escape在没有文本命令优先级冲突时查找当前可见entry的预声明close event，执行同一action和alpha表；它不是通用的overlay遍历器。

## 5. 安全与可审计proof

v1拒绝以下典型攻击：

| 攻击 | 拒绝条件 |
|---|---|
| `initial` | 非二元initial visibility，或不同于State Slot初始值。 |
| `offset` | quad offset未按44-byte对齐、越界或不递增。 |
| `tile` | tile越界，或与每个open/close action的预证明scope不同。 |
| `disable` | `overlay_state_required=true`但计划为`false`。 |

同时，已有rounded/shadow、font placement、event map、action slot、release motion及visual canvas proof继续生效。普通desktop静态overlay不会仅因其primitive tag存在而被错误拒绝。

## 6. 已验证示例

[`examples/material-overlay-showcase.rkt`](examples/material-overlay-showcase.rkt) 产生一个初始关闭的 `deployment-overlay`。它有一个open action、五个close action、26个quad alpha地址、120个glyph alpha槽和一个固定tile。真实X11/Vulkan回归验证open、Escape、scrim、confirm与menu-copy关闭端点；结构oracle和四类Scene篡改拒绝入口见 [`tools/verify_overlay_state_plan.sh`](tools/verify_overlay_state_plan.sh)。

## References

[1] [Racket compiler lowering and Scene serialization](noir/ui/main.rkt)
[2] [Rust startup proof and fixed-alpha executor](wgpu-verify/src/bin/noir_winit_host.rs)
[3] [End-to-end regression](tools/verify_overlay_state_plan.sh)
