# Static Multi-Field Event 与 Batch-Fusion Proof

**状态：** 已实现静态 DSL fixture、Scene proof ABI、Rust 启动期再验证、真实 X11/Vulkan 鼠标回归与 timestamp benchmark。

## 1. 研究目标

Noir 的下一步不是让运行时“聪明地合并”多个局部更新，而是让编译器提前给出唯一合法的融合请求。当一个静态事件已知会触发多个 field-local 依赖时，编译期应固定：成员 worklist slots、精确 packet union、tile union、策略以及 renderer 的融合 slot。

> runtime 只执行 `compiled batch id → fused RenderRequest`；它不会扫描 UI tree、重新合并 packet、排序 task 或猜测 tile coverage。

## 2. 新 DSL fixture

新增 `multi-field-event`，它只能接受字面 `#:id`、`#:transaction` 和 `#:operation commit|reset`：

```racket
(multi-field-event #:id fuse-commit
                   #:transaction apply-all
                   #:operation commit
                   #:width 180 #:height 12
                   "Fuse Commit")
```

该构造在 macro expansion 中内联为普通 `transaction-button`。它不引入新的 runtime widget、回调闭包或成员列表。transaction plan 已在编译期决定三个 member field，随后 composite worklist lowering 产生 batch-local slot。

独立 fixture：`examples/composite-worklist-dashboard.rkt`。它有三个 field-local worklists：slot 3→packet 3，slot 4→packet 6，slot 5→packet 9，以及两个静态事件 `fuse-commit` 与 `fuse-reset`。

## 3. Batch-Fusion Proof ABI

对任何有两个以上非空 member local slots 的 `frame_coalesced_batch`，Scene JSON 现在携带：

```json
"batch_fusion_proof": {
  "member_worklist_indices": [3, 4, 5],
  "fused_worklist_index": 7,
  "fused_packet_indices": [3, 6, 9],
  "fused_tile_ids": [0, 1, 2, 3],
  "strategy_id": "coalesced"
}
```

| Artifact | `fuse-commit` | `fuse-reset` |
|---|---:|---:|
| Member local slots | `[3,4,5]` | `[3,4,5]` |
| Fused worklist slot | `7` | `8` |
| Exact packet union | `[3,6,9]` | `[3,6,9]` |
| Fused tile IDs | `[0,1,2,3]` | `[0,1,2,4]` |
| Strategy | `coalesced` | `coalesced` |

所有其它 batch 写入 JSON `null`，而不是布尔 `false`，使Rust `Option<BatchFusionProof>` ABI严格一致。

## 4. 编译期与启动期不变量

Racket `compile-composite-batch-worklists` 从 transaction task 的 compiler-emitted `packet_worklist_indices` 读取 constituent field-local slots，执行 canonical sort/dedup/union，并且在 macro expansion 时验证 selected worklist payload 与 union 完全相同。

Rust `compiler_coalesced_batches` 在窗口创建前重建 member slot union，并检查 `BatchFusionProof` 的五项字段：member slots、fused slot、packet union、tile union、strategy ID。多成员 batch 还必须引用 `batch-` 前缀的 compiler-generated worklist。

篡改测试将 `fuse-commit` 的 `fused_tile_ids` 从 `[0,1,2,3]` 改为 `[0,1,2]`；release host 启动期拒绝 Scene：

```text
batch-fusion proof disagrees with immutable batch artifact
```

## 5. 真实验证

| 检查 | 结果 |
|---|---|
| Racket 全量回归 | 通过 |
| Fixture Scene 导出 | 通过；产生 slot 7/8 和两个 batch fusion proof |
| Rust `cargo check` / release build | 通过 |
| 真实 X11 鼠标 oracle | 通过 |
| Scalar/reference packet differential | 继续通过 |
| 篡改 packet/tile proof | 启动期拒绝 |
| 当前 timestamp benchmark | 两个 fixture activation 均 `expectations_match=true` |

`tools/verify_multifield_event_fusion.sh` 在 Xvfb 中点击编译器 Event Map 固定的两个按钮坐标。每次点击观察到：一个 coalesced batch、一个 `RenderRequest`（commit slot 7 / reset slot 8）和一个 workgroups=3 的 packet activity dispatch。

## 6. 性能边界

该 fixture 已证明融合 request 的可执行 ABI，但当前 transaction lowering 在实验前就具备 transaction-local union，因此它不是严格的 `3 queue submissions → 1 queue submission` 对照。当前真实 timestamp 数据仅证明 fusion artifact 进入 release renderer 路径：

| Case | CPU event-to-submit | GPU timestamp | Contract |
|---|---:|---:|---|
| `coalesced-activate-fuse-commit` | 155.9 µs | 1007.7 µs | match |
| `coalesced-activate-fuse-reset` | 162.9 µs | 714.6 µs | match |

下一阶段应让三个独立 field task 各自产生一项 compiler-tagged `RenderRequest`，保留一个 baseline executor，并在 fusion executor 中按 `batch_fusion_proof` 把三项替换为一项。届时可以用相同 Scene、同一 adapter、多轮采样严格比较 dispatch count、queue submit count、CPU event-to-submit 与 GPU elapsed。

## 7. 可复现命令

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
PLTCOLLECTS="$PWD:" NOIR_ENTRY_MODULE="examples/composite-worklist-dashboard.rkt" \
  racket tools/export-dashboard.rkt out/composite-worklist-dashboard.scene.json
cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host
tools/verify_multifield_event_fusion.sh
```
