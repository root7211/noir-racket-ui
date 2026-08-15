# Noir Profile-Guided Strategy Lowering

**作者：Manus AI**  
**范围：** `#lang noir/ui` 宏展开期 Profile Schema 读取、Replay Matrix 成本 lowering、完整 action batch 的固定 `strategy_id` 与 Scene JSON proof。  
**目标：** 将真实 wgpu Replay Matrix 的设备特定成本在 Racket 编译期冻结为可执行策略选择；发布后的 Rust host 不读取 profile、不比较时间、不自适应选路。

> 选择策略的单位是完整的 Coalesced Activate Batch，而不是单个 action。这样 release 的按钮视觉恢复、action 的业务 state update、winner-only GPU writes 与 merged tile IDs 都保留在同一个语义边界内。

## 1. Profile Schema v2

`profiles/registry.json` 从 `registry_version: 1` 升级为 `2`。既有 `matcher`、timestamp metadata、基础 cost coefficients 和 calibration samples 原样保留；新增 `replay_strategy_costs` 记录来自 `noir-wgpu-replay-matrix-v1` 的冻结结果。

| 字段 | 含义 | 编译器约束 |
|---|---|---|
| `schema` | 必须为 `noir-wgpu-replay-matrix-v1` | 不匹配则报宏展开期错误 |
| `semantic_group` | 必须为 `complete-activate-v1` | 只允许语义等价候选比较 |
| `selection_metric` | 必须为 `gpu_median_ns` | 当前 winner 的唯一成本指标 |
| `source` | report、adapter、warm-up、samples、timestamp period | 审计来源；不进入 runtime |
| `batches[].batch_id` | compiler `coalesced-activate-*` 的稳定 ID | 必须精确匹配 |
| `candidates[]` | `full-redraw`、`packet-aware`、`coalesced` 的实测 cost/work metrics | 三者缺一不可 |

每个 candidate 至少固定 `gpu_median_ns`、`gpu_p95_ns`、`cpu_median_ns`、tile/glyph work metrics 与 `winner_write_bytes`。本次冻结的 profile 对应 Vulkan/llvmpipe replay matrix，故只用于该 adapter matcher 与 CI 可重复性，而不是物理 GPU 的通用性能宣称。

## 2. 同语义策略规则

完整 activate 的候选顺序固定为：

```racket
(define replay-strategy-order '(full-redraw packet-aware coalesced))
```

编译器严格过滤 `semantic_group = "complete-activate-v1"`。`action-aware` 只执行业务 action 的 4/12-byte write 和一个 action tile，刻意省略 release 按钮恢复；它是下界测量而非完整 pointer-up 激活，因此不会、也不能进入自动选择候选。

| Candidate | 是否与完整 activate 等价 | 是否可被自动选择 |
|---|---:|---:|
| `full-redraw` | 是 | 是 |
| `packet-aware` | 是 | 是 |
| `coalesced` | 是 | 是 |
| `action-aware` | 否；没有 release visual semantics | 否 |

winner 使用 `gpu_median_ns` 的严格最小值。成本完全相等时，固定的候选顺序成为 tie-break：`full-redraw`、`packet-aware`、`coalesced`。该 tie-break 同样写入 proof，避免任何 hash iteration 或 runtime 排序的不稳定性。

## 3. 核心 Racket lowering

Profile loader 已在宏展开期冻结 `active-cost-profile`。新增的 `replay-candidates-for` 执行 schema、semantic group、metric、候选完整性及非负成本检查。`choose-replay-strategy` 随后生成扩展后的 `c-coalesced-batch`：

```racket
(struct c-coalesced-batch
  (id task-ids execution-order winner-writes eliminated-writes
   merged-tile-ids conflict-edges strategy-id candidate-costs selection-proof)
  #:transparent)
```

其核心 winner fold 是：

```racket
(for/fold ([best (car replay-strategy-order)])
          ([strategy (in-list (cdr replay-strategy-order))])
  (if (< (hash-ref costs strategy) (hash-ref costs best)) strategy best))
```

由于只在严格更小时替换 winner，相等成本自然保留先出现的 strategy。`compile-profile-guided-batch-strategies` 进一步证明 activate batch 的 candidate key 集合恰好为三个语义等价策略，且 `strategy_id` 成本等于 candidate costs 的最小值。

## 4. Scene JSON ABI

每个 `frame_coalesced_batches[]` 现在包含：

```json
{
  "id": "coalesced-activate-refresh-fps-button",
  "strategy_id": "coalesced",
  "candidate_costs": {
    "full-redraw": 684366.0,
    "packet-aware": 561036.0,
    "coalesced": 274298.0
  },
  "selection_proof": {
    "mode": "profile-guided",
    "profile_id": "noir-vulkan-gpu-matrix-v1",
    "semantic_group": "complete-activate-v1",
    "selection_metric": "gpu_median_ns",
    "source_batch": "coalesced-activate-refresh-fps-button",
    "winner": "coalesced",
    "tie_break_order": ["full-redraw", "packet-aware", "coalesced"]
  }
}
```

三条 activate batch 都选择 `coalesced`：progress 为 `373,460 ns`，FPS 为 `274,298 ns`，latency 为 `294,295 ns`。三条 press batch 不属于 complete activate group，输出 `strategy_id: "coalesced"` 与 `mode: "non-activate-batch"`，不伪装为基于设备测量的自动选择。

当未提供 `NOIR_COST_PROFILE` 或 `NOIR_PROFILE_ID`，或者 registry 中不存在该 activate batch 时，compiler 显式输出 `mode: "profile-unavailable"` 与 `strategy_id: "coalesced"`。这确保没有 profile 的构建仍保留既有正确的完整交互语义，而不会静默猜测设备。

## 5. 验证证据

Profile build：

```bash
PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tests/run.rkt
```

回归 oracle 验证三条 activate batch 均具有：

| 不变量 | 结果 |
|---|---|
| candidate key 集合 | 恰为 `coalesced`、`full-redraw`、`packet-aware` |
| `action-aware` | 不存在于 candidate costs |
| winner | `coalesced` |
| winner cost | 等于三个 candidate 的最小 `gpu_median_ns` |
| proof mode | `profile-guided` |
| proof group / metric | `complete-activate-v1` / `gpu_median_ns` |

无 profile 回归同样通过，确认 fallback 不破坏基础 DSL。含扩展 batch 字段的 `out/profile-strategy.scene.json` 已在真实 Vulkan/llvmpipe、wgpu Surface、Xvfb、X11 `xdotool` 的端到端输入中执行：winner-only writes、merged tile masks、3-instance metrics glyph draw 与 progress 的零 glyph draw 都保持不变。

## 6. 宿主消费边界

Rust host 当前可以向后兼容解码该 Scene，因为未消费的 JSON metadata 不改变既有 Coalesced Batch ABI 字段。这个阶段的职责是让 compiler **固定并证明**策略，而不是在 host 内再次选择策略。

下一阶段应为 Rust host 增加对 `strategy_id` 与 `selection_proof` 的启动期验证，并将完整 activate batch 的全量/packet/coalesced executor 明确绑定到 compiler 的 strategy。届时 host 只检查 compiler choice 是否是 profile proof 的 winner，然后执行，不重新读取 profile 或比较成本。

## 7. 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/profile-strategy.scene.json

PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tests/run.rkt

./tools/verify_winit_host.sh out/profile-strategy.scene.json
```
