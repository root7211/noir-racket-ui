# Noir Row Activation：编译产物到真实 X11/wgpu 闭环报告

**作者：** Manus AI  
**范围：** `#lang noir/ui` 的 `(on-activate action-id)`、Scene JSON `row_activation_plans`、Rust/wgpu X11 宿主、真实鼠标行释放与 Enter。  
**结论：** Row Activation 已形成一条没有运行时 UI 树查找、action 名称解析、tile 合并或 worklist 生成的闭环。运行时只读取已选中的 logical row，调用启动期证明过的 coalesced batch，并把预先确定的 GPU 写入与局部渲染请求送入既有 FIFO。

> 本交付将“列表行被激活”从一个动态回调问题收束为静态数据流：**input → selected logical row → compiled row-activation plan → Action Slot / coalesced batch → winner writes + fixed worklist slot → RenderRequest → wgpu**。

| 层级 | 固定工件 | 运行时所做的工作 |
|---|---|---|
| DSL 前端 | `(on-activate refresh-tick)` | 无 DSL 解释或回调查找 |
| 编译器 | `row_activation_plan`、Action Slot `0`、batch ID、action tile mask、worklist `2` | 无 action ID 解析 |
| 启动期宿主 | list / slot / batch / tile / worklist 的交叉 proof | 一次性拒绝不一致 Scene |
| 输入热路径 | selected logical row 与 physical slot `logical mod physical_slots` | 调用唯一 coalesced batch 执行器 |
| GPU 路径 | winner-write byte ranges、resident no-packets worklist、局部 tile mask | buffer patch、dynamic uniform slot 选择、局部提交 |

## 1. 最终静态 ABI

10,000 行 `data-register-table` fixture 的编译器输出包括下列唯一 row activation artifact。它把列表、动作、canonical Action Slot、activate batch、Action 本身的 tile scope，以及 packet worklist 一次性固定下来。[1]

```json
{
  "list_id": "telemetry-registers",
  "action_id": "refresh-tick",
  "action_slot_index": 0,
  "activate_batch_id": "coalesced-activate-refresh-registers",
  "tile_mask": 1,
  "packet_worklist_index": 2,
  "strategy_id": "coalesced",
  "physical_slot_rule": "logical-mod-physical-slots"
}
```

| ABI 字段 | 固定值 | 安全与性能含义 |
|---|---:|---|
| `list_id` | `telemetry-registers` | 行事件只可属于已编译 virtual list。 |
| `action_slot_index` | `0` | 将 `refresh-tick` 降为 canonical Action Slot，不在输入期查 action map。 |
| `activate_batch_id` | `coalesced-activate-refresh-registers` | 复用已验证 winner-write order。 |
| `tile_mask` | `0x1` | artifact 保存 Action 自己更新 tick text 的局部 tile。 |
| `packet_worklist_index` | `2` | 指向 GPU 常驻 `no-packets=[]`，禁止扩大 packet activity 写范围。 |
| `physical_slot_rule` | `logical-mod-physical-slots` | logical row 仅映射到固定 row recycling ring 的 physical slot。 |

这里有一个刻意保留的语义区别：row artifact 的 `tile_mask=0x1` 是 **Action 局部 scope**；activate batch 的实际提交 mask 是 `0x3`，因为同一 coalesced batch 还包含 release transient 的 tile 1。启动期 proof 因而验证 `batch.tile_mask & artifact.tile_mask == artifact.tile_mask`，而不是错误地要求相等。这样既证明 Action 的刷新范围没有被遗漏，又允许其与固定 transient release 一起在单个 batch 内提交。[1] [2]

## 2. Rust 消费与反向 proof

Rust `Scene` 现在反序列化 `RowActivationPlan`，并在 `Host::new` 期间将其降低为仅含索引、batch ID、action tile mask 和 worklist index 的 `CompiledRowActivationPlan`。启动时的 `compiler_row_activation_plans` 不是“尽量接受” JSON，而是逐项建立如下不变量。[2]

| Proof 条件 | 交叉来源 | 拒绝的错误类别 |
|---|---|---|
| 每个 `list_id` 唯一且存在 | `virtual_list_plans` | 重复计划、未知列表 |
| `physical_slot_rule` 精确为 ring ABI | literal rule | 动态或非固定 slot 映射 |
| `action_slot_index → action_id` 完全一致 | canonical `action_slots` | slot 越界、字符串/slot 撕裂 |
| artifact tile mask 等于 Action Plan mask | action tile map | action 刷新范围被扩张或改写 |
| `strategy_id == coalesced` | literal strategy | 将运行期交给策略猜测 |
| batch 含同一个 `Action(index)` task ref | `CompiledBatch.execution_refs` | batch 与动作脱钩 |
| Action tile mask 是 batch tile mask 的子集 | compiled batch tiles | activate batch 遗漏动作损伤区域 |
| batch 与 artifact 均引用 slot `2` | composite worklist + artifact | packet worklist 偷换或扩大 |
| slot `2` 的 packet table 为空 | resident packet worklists | 不必要的 packet compute activity |

通过 proof 后，`Host` 只保留结构化计划。`activate_selected_list_row_for` 读取 selection table 中的 logical row，按 `logical % physical_slots` 取得仅用于审计的 physical slot，然后调用既有 `execute_coalesced_batch`。因此 winner-write 排序、Action state write、glyph patch、batch-local worklist 和 `RenderRequest` 入队都仍然由单个已验证执行器处理，而不是另建一条易漂移的 row 专用路径。[2]

## 3. 输入期行为

生产事件路径已接入两个入口。鼠标左键释放落在列表 row 时先沿现有 selection path 固定 logical row，然后立即执行 row activation；Enter 则先尝试 activation，只有没有任何 selected row 对应 activation plan 时才回退到原有普通 keyboard command 分派。这样不会破坏 form、text editing 或已有 Enter command 的优先级。[2]

| 输入 | 固定选择 | 结果 |
|---|---|---|
| Row release | cursor → static list viewport / row height → selected logical row | selection color patch 后执行对应 row activation batch |
| Enter | `list_selected_rows[list_index]` | 执行对应 row activation batch；若无匹配 plan 则执行原 keyboard command |
| `--inject-list-release list logical` | 集成测试选择入口 | 复用 production selection path |
| `--inject-row-activate list` | 集成测试激活入口 | 要求已存在 selected row，并复用同一 activation executor |

该选择逻辑仍是固定容量：fixture 可表达 10,000 个 logical rows，但 GPU row arena 只有 4 个 physical slots；本次真实验证使用 logical row `1`，可审计 physical slot 为 `1`。没有为 row activation 增加一条按 logical row 分配 GPU buffer 的路径。[1] [2]

## 4. 真实验证结果

所有验证均使用仓库实际 Scene、release Rust 二进制、X11-only winit 和 `WGPU_BACKEND=vulkan`。Xvfb 环境的 Vulkan adapter 仍会产生 DRI3/llvmpipe 类软件渲染告警；这些告警不影响 wgpu pipeline、buffer writes、packet activity dispatch 或 oracle 的执行。测试断言的是宿主日志中的实际执行事件，而不是静态源文本。

| 验证 | 实际命令或工件 | 结果 | 关键证据 |
|---|---|---|---|
| Racket 全量回归 | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 通过 | 现有 GUI 编译期 artifact 全量 oracle 未回归。 |
| Rust 静态检查 | `cargo check --bin noir_winit_host` | 通过 | 新 ABI、proof、input 分派和注入入口通过类型检查。 |
| Rust release 构建 | `cargo build --release --bin noir_winit_host` | 通过 | 仅保留既有非阻塞 warning。 |
| Scene 启动期 proof | 10,000 行 fixture 的 release X11/Vulkan 启动 | 通过 | `compiler row activation: ... slot=0 ... tile-mask=...1 worklist=2`。 |
| 注入闭环 | synthetic selection row 1 → `--inject-row-activate` | 通过 | `tick` 从 0 加至 1、3 个 glyph ID patch、mask `0x3` request、no-packets skip。 |
| **真实 X11 行释放 + Enter** | `tools/verify_row_activation.sh` | **通过** | 鼠标释放生成第 1 次 action，真实 Enter 生成第 2 次 action；tick 分别为 1、2。 |
| 篡改负向 proof | 将 artifact worklist `2` 改为 `1` 后启动 | **拒绝，符合预期** | 启动返回 code 1，并报告 `row activation telemetry-registers widened packet worklist`。 |

真实 X11 脚本对 winit 窗口发送 row 1 的鼠标点击/释放，再显式将焦点设回该窗口后发送 Enter。日志确认两次输入都调用了相同的 batch：

```text
row-activation: list=telemetry-registers logical=1 physical=1 action-slot=0 \
  batch=coalesced-activate-refresh-registers action-tile-mask=0x0000000000000001 worklist=2
coalesced-batch execute: coalesced-activate-refresh-registers \
  refs=[Transient(2), Action(0)] worklist_slots=[2, 2]
state-slot write: action=refresh-tick state=tick index=0 op=add value=1
render-request-enqueue coalesced-activate-refresh-registers: \
  mask=0x0000000000000003 strategy=None worklist=2

... Enter ...

state-slot write: action=refresh-tick state=tick index=0 op=add value=2
```

这说明 row release 与 Enter 没有产生第二套“列表 action 执行器”。两者都落到同一个 fixed batch、同一个 `no-packets` resident slot 和同一个局部 `RenderRequest` shape。[2] [3]

## 5. GPU 写入与渲染边界

本闭环的核心不是“点击后能改文本”这一表面功能，而是点击后的所有 GPU 工作仍保持编译期边界。`refresh-tick` 的 action winner writes 只更新固定 3 个数字 glyph cell；activate batch 还包含固定 release transient 的 position/color byte ranges。渲染器提交的是两个预知 tile 的 mask `0x3`，且 worklist slot `2` 为空，因此 packet activity compute 明确记录为 skip，不对 packet activity 或 indirect command buffer 产生额外范围写入。[1] [2]

| 阶段 | 动态输入 | 编译期固定对象 | 运行期禁止的工作 |
|---|---|---|---|
| selection | logical row | list dimensions、row height、ring slot rule | 遍历 UI tree、计算布局 |
| activation | selected row presence | Action Slot、batch ref、winner writes | action name dispatch、任务排序 |
| state/GPU patch | `tick += 1` | state slot 0、3 glyph offsets、release byte ranges | shape text、分配 patch buffer |
| renderer | batch request | tile mask、strategy、worklist slot | 合并 tile、构造 packet worklist、上传 worklist payload |

## 6. 新增可复现实验入口

新增 `tools/verify_row_activation.sh`。它会启动 Xvfb、运行 release host、发现 winit 窗口、对固定 row 1 发送真实鼠标释放与 Enter，并断言两次 action 均走固定 row activation ABI。脚本没有模拟 Rust 方法调用；鼠标和键盘事件都由真实 X11 event loop 接收。[3]

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host
./tools/verify_row_activation.sh
```

Racket 侧全量编译期回归和负向 proof 也可复现：

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt

SCENE=out/data-register-table-10000.scene.json
sed 's/"packet_worklist_index":2,"physical_slot_rule"/"packet_worklist_index":1,"physical_slot_rule"/' \
  "$SCENE" >/tmp/noir-row-activation-tampered-worklist.scene.json
DISPLAY=:95 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  wgpu-verify/target/release/noir_winit_host /tmp/noir-row-activation-tampered-worklist.scene.json
# 预期：启动失败，报告 widened packet worklist。
```

## 7. 对“编译型极致性能 GUI”的意义

Row activation 是 virtual list 从“能滚动、能选中”进入“用户动作能穿透静态 compiler artifact 并影响业务状态”的关键点。此前 row selection 已是固定颜色 patch；现在 selection 的 logical identity 能以零动态 action lookup 的方式进入 Action Slot ABI。它证明了 10,000 logical rows 并不迫使运行时出现 10,000 个 callback、GPU node 或 packet plan。

> 运行时不决定“这个 row 应执行什么”；它只证明“当前选择是否对应编译器已经许可的 row activation plan”，然后执行唯一的短路径。

这为下一阶段冻结 virtual-list 底层 ABI 提供了足够的实证基础。建议冻结的字段包括 logical capacity、physical slots、visible rows、row height、row tile arena、`logical-mod-physical-slots`、list interaction color offset table，以及本报告中的 `row_activation_plans` 八字段 ABI。冻结后再将工作重心转移到 scrollbar track/thumb 与 PageUp/PageDown/Home/End，而不是继续改动 action/path 的底层表示。

## 8. 已知边界与后续工作

当前 release 验证使用软件 Vulkan/llvmpipe 环境，因此它证明的是**真实 wgpu/X11 命令路径、范围约束与功能闭环**，不是离散 GPU 吞吐量结论。后续若进行性能比较，应在同一硬件与同一驱动上对 Noir 与 GPUI 运行相同的 long-list navigation / activation workload，并报告 event-to-submit、queue submit、timestamp、CPU utilization 和 frame pacing，而不将本报告中的 correctness evidence 外推为硬件优势。

下一个功能阶段应严格沿以下顺序进行：先冻结已通过的 virtual-list + row activation ABI；随后实现 fixed scrollbar track/thumb、PageUp/PageDown/Home/End 的静态 transition table；最后以日志浏览器与实时监控表格两个用户可见示例验证 ABI 的可用性。除非新的输入类型确实无法表示为现有 dataflow，否则不应引入动态 callback registry、运行时 layout search 或 action string dispatch。

## References

[1]: [10,000 行 data-register-table Scene artifact](out/data-register-table-10000.scene.json)  
[2]: [Rust X11/wgpu host：Scene ABI、反向 proof、执行器与事件循环](wgpu-verify/src/bin/noir_winit_host.rs)  
[3]: [真实 X11 row release + Enter 回归脚本](tools/verify_row_activation.sh)  
[4]: [Racket `#lang noir/ui` 编译器及 Action Slot Resolution Pass](noir/ui/main.rkt)
