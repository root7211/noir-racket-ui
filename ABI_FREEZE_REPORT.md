# Noir Virtual List / Row Activation ABI v1：冻结交付记录

**作者：** Manus AI  
**状态：** 已实现并验证  
**冻结对象：** `virtual_list_plan` 与 `row_activation_plan` 的 Racket compiler → Scene JSON → Rust/wgpu host 接口。

## 1. 冻结结论

Noir 已将 virtual list 与 row activation 从“当前实现碰巧一致”的约定升级为显式的、版本化且默认拒绝漂移的 ABI。Racket 会在每个 artifact 与顶层 Scene 中发出精确 schema/revision；Rust 在任何 list geometry、row recycling、Action Slot 或 GPU 写入 proof 之前验证这些 contracts。错误版本、错误 artifact schema 或必需字段遗漏都会终止启动，而不会回退到 serde 默认值或旧语义。[1] [2]

> **ABI v1 的核心承诺：** 后续 scrollbar、PageUp/PageDown/Home/End 和用户示例只能引用既有的 list ID、fixed geometry、physical ring、row address tables、Action Slot 与 batch ref；它们不能重定义这些字段的含义。

| 工件 | Schema | Revision | 主机策略 |
|---|---|---:|---|
| `virtual_list_plans[]` | `noir-virtual-list-plan-v1` | 1 | 仅接受精确匹配；缺少任何冻结字段即 JSON 解析失败。 |
| `row_activation_plans[]` | `noir-row-activation-plan-v1` | 1 | 仅接受精确匹配；之后继续执行 Action Slot/batch/tile/worklist 反向 proof。 |
| `abi_contracts` | 同时声明上述两项 | 1 | 每个 Scene 启动时优先验证；不允许旧 host 或旧 artifact 静默混用。 |

## 2. Racket 编译器实现

`noir/ui/main.rkt` 现在保存了两项唯一真源常量与 `abi-contracts->jsexpr`。`scene->jsexpr` 无条件导出顶层 `abi_contracts`，而 `virtual-list-plan->jsexpr` 和 `row-activation-plan->jsexpr` 分别导出 `abi_schema`、`abi_revision`。这使 ABI 标识与实际 lowering 在同一个编译器模块中生成，而非由构建脚本或宿主臆测。[1]

编译后的 10,000 行 Scene 含有如下形状：

```json
{
  "abi_contracts": {
    "virtual_list_plan": {"schema": "noir-virtual-list-plan-v1", "revision": 1},
    "row_activation_plan": {"schema": "noir-row-activation-plan-v1", "revision": 1}
  },
  "row_activation_plans": [{
    "abi_schema": "noir-row-activation-plan-v1",
    "abi_revision": 1,
    "list_id": "telemetry-registers",
    "action_slot_index": 0
  }],
  "virtual_list_plans": [{
    "abi_schema": "noir-virtual-list-plan-v1",
    "abi_revision": 1,
    "id": "telemetry-registers"
  }]
}
```

## 3. Rust 严格准入实现

Rust `Scene` 新增强制 `abi_contracts` 字段，并为 `VirtualListPlan`、`RowActivationPlan` 增加无默认值的 schema/revision 字段。原来可以由 `#[serde(default)]` 填补的 virtual list geometry、logical/physical capacity、row address table、subrange、visible tile 与 scroll transition 字段已经改为必需字段。Scene 若只缺少 `row_glyph_slots`，甚至不会走到 Host 初始化，serde 即会拒绝它。[2]

`compiler_abi_contracts` 会在 `compiler_virtual_list_plans` 前运行，要求顶层 `virtual_list_plan` 与 `row_activation_plan` contracts 都精确等于 v1。之后，`compiler_virtual_list_plans` 与 `compiler_row_activation_plans` 会各自重新检查具体 artifact 的 schema/revision；这是对“顶层宣称 v1、元素实际混入其他版本”的防护。

| 准入层 | 证明对象 | 拒绝示例 |
|---|---|---|
| Scene contract | 顶层 schema/revision | `virtual_list_plan v9` 被拒绝。 |
| Artifact contract | 每一项 list / activation plan | `row_activation_plan-v9` 被拒绝。 |
| serde field boundary | v1 必需字段 | 删除/改名 `row_glyph_slots` 被拒绝。 |
| 既有语义 proof | geometry、physical ring、GPU offsets、Action Slot、batch、tiles、worklist | 任意地址或范围漂移继续由既有 proof 拒绝。 |

## 4. 验证结果

所有测试使用 Racket 实际导出的 Scene、release winit 宿主与 `WGPU_BACKEND=vulkan`。Xvfb/llvmpipe 只作为无窗口硬件环境；验证对象是实际 X11 event loop、wgpu device、Scene serde、Host startup proof 与 GPU command path，而非源代码字符串比较。

| 验证 | 结果 | 关键实际证据 |
|---|---|---|
| Racket 全量回归 | 通过 | 所有既有 DSL fixture 可输出包含 contracts 的 Scene。 |
| Rust `cargo check` | 通过 | 新类型、强制字段和 proof 函数通过 Rust 1.75 构建。 |
| Rust release 构建 | 通过 | release `noir_winit_host` 已包含冻结准入。 |
| ABI v1 正向 X11/Vulkan 启动 | 通过 | `compiler ABI contracts: virtual-list=noir-virtual-list-plan-v1@1 row-activation=noir-row-activation-plan-v1@1 frozen`。 |
| 顶层 contract revision 篡改 | 按预期拒绝 | `unsupported virtual_list_plan ABI ...@9; expected ...@1`。 |
| row activation artifact schema 篡改 | 按预期拒绝 | `row activation telemetry-registers has unsupported ABI ...v9@1`。 |
| 必需字段遗漏 | 按预期拒绝 | `missing field row_glyph_slots`。 |
| 真实行释放 + Enter 回归 | 通过 | 两次都复用 fixed row activation batch，`tick` 依次为 1、2。 |

独立脚本 `tools/verify_frozen_list_abi.sh` 会重新导出 Scene、启动 release host、验证 v1 正向准入，再自动生成三种篡改 Scene 并断言拒绝。它是后续引入 scrollbar 前必须保持通过的 ABI oracle。[3]

## 5. 对下一阶段的约束

Scrollbar 的 DSL、Scene artifact 与 Rust executor 必须作为新的版本化工件实现，例如 `scrollbar_plan`。它最多可以引用 `virtual_list_plan.id`、固定 scissor geometry、`visible_rows`、`logical_capacity`、`physical_slots` 和已有 scroll executor；不能修改 v1 `row_draw_ranges`、`row_glyph_subranges`、row-tile rule、worklist 语义或 `row_activation_plan` batch 语义。

建议下一次实现按下列窄路径开始：静态 scrollbar track/thumb geometry → pointer coordinate clamp → pre-proved logical viewport target → `apply_compact_register_scroll` → 既有 viewport-only `RenderRequest`。任何需要动态布局、GPU资源分配、packet worklist构造或字符串 Action dispatch 的 scrollbar 方案都违反本冻结记录，应当拒绝。

## References

[1]: [Racket ABI常量、Scene encoder与artifact JSON lowering](noir/ui/main.rkt)  
[2]: [Rust ABI structs、严格serde边界与启动期proof](wgpu-verify/src/bin/noir_winit_host.rs)  
[3]: [ABI冻结正向/负向回归脚本](tools/verify_frozen_list_abi.sh)  
[4]: [v1正式接口规范](VIRTUAL_LIST_ROW_ACTIVATION_ABI_V1.md)
