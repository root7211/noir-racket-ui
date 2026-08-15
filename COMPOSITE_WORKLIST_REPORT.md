# Compiler-Proved Composite Worklist：多 Local Worklist 的单 Dispatch Lowering

**状态：** 已实现并通过 Racket compiler oracle、Rust 启动期反向 proof、真实 X11 鼠标输入、wgpu/Vulkan 渲染与真实 GPU timestamp benchmark 验证。

## 1. 目标

Noir 的运行时不应在一个 coalesced batch 发生后扫描 UI、查询依赖图、合并 glyph range 或猜测哪个 worklist 能安全使用。对于一个静态事务，编译器早已知道所有受影响 field 的 local packet worklist；它应在 macro expansion 期生成**精确、有序、去重的 packet union**，并把这个 union 作为 batch-local immutable artifact 交给 renderer。

> `input → compiled batch ref → compiler-proved member slots → exact packet union slot → one packet activity compute dispatch`

这条路径的关键安全条件是：composite worklist 必须严格等于成员 local worklist 的 packet index 并集；它不允许把“全部 dynamic packets”当作方便的近似，也不允许因合并而扩大 GPU compute 范围。

## 2. 编译期实现

### 2.1 新增 ABI

`frame-task` 与 `c-frame-task` 新增 `packet_worklist_indices`。它与原有单值 `packet_worklist_index` 的职责不同：

| 字段 | 语义 |
|---|---|
| `packet_worklist_index` | 该 task 原有单一 renderer slot；普通视觉任务固定为 `no-packets`，transaction task 可指向 transaction-local union |
| `packet_worklist_indices` | 用于 batch proof 的 constituent local slots；transaction task 在编译期保留所有 field-local dependencies |

`frame-coalesced-batch` 和 `c-coalesced-batch` 新增以下 immutable proof fields。

| 字段 | 含义 |
|---|---|
| `composite_worklist_index` | renderer 必须直接使用的 compiler-fixed slot |
| `composite_worklist_member_indices` | 参与 union 的非空 local slot，canonical ascending order |
| `composite_worklist_packet_indices` | canonical ascending packet union |

### 2.2 Lowering 规则

`compile-composite-batch-worklists` 在 task-local annotation、conflict graph 与 frame coalescing 之后运行，但在 profile strategy selection 之前运行。它对每个 batch：

1. 收集每个 member task 的 `packet_worklist_indices`；若成员列表为空，使用其单一 `packet_worklist_index`；
2. 删除空 worklist，按索引去重并排序；
3. 对成员列表的 packet indices 作去重、升序 union；
4. 成员数为 0 时指向 `no-packets`；成员数为 1 时复用已有 slot；成员数大于 1 时在 packet worklist table 末尾追加 `batch-<batch-id>` slot；
5. 在 macro expansion 时重新计算一次 union，并断言 selected slot 的 payload 与 proof 完全相同。

这样 batch-local worklist 的生成不是运行时优化，也不是 heuristic；它是 compiler output 的一部分。

## 3. Settings Form 实验场景

Settings Dashboard 的 `apply-all` / `reset-all` transaction 已有三个 field-local slot：

| Field | Local slot | Packet |
|---|---:|---:|
| `sample-interval-row$field` | 3 | 3 |
| `alert-threshold-row$field` | 4 | 6 |
| `batch-size-row$field` | 5 | 9 |

编译器为两个 pointer activation batch 新增以下 worklists：

| Batch | Composite slot | Member slots | Exact packet union |
|---|---:|---:|---:|
| `coalesced-activate-apply-all-button` | 7 | `[3, 4, 5]` | `[3, 6, 9]` |
| `coalesced-activate-reset-all-button` | 8 | `[3, 4, 5]` | `[3, 6, 9]` |

两者的 packet union 与既有 `transaction-apply-all` 只是内容相同；不同之处在于 slot 7/8 的**所有权和正确性证明属于具体 coalesced batch**，而不是由Rust按“最后一个非空task slot”推断。该所有权在未来 batch 由多个独立 field/action task 构成时仍成立。

## 4. Rust 消费与反向验证

`compiler_coalesced_batches` 现在在启动期从 immutable member task slots 重建 expected member set 与 expected packet union，并检查：

- Scene 中的 member slots 与重建结果相同；
- Scene proof 的 packet list 与重建 union 相同；
- selected worklist 的 payload 与 union 相同；
- 多成员 union 必须引用名字以 `batch-` 开头的 compiler-generated slot。

`apply_compiler_batch_writes` 不再从 `task_worklist_indices` 选最后一个非空 slot。它执行 winner writes 后直接返回 `CompiledBatch.composite_worklist_index`，将其作为显式 `RenderRequest.packet_worklist_index` 提交。

反向篡改测试将 `Apply All` proof 由 `[3,6,9]` 改为 `[3,6]`。release host 在窗口创建前拒绝 Scene：

```text
coalesced batch coalesced-activate-apply-all-button
composite packet proof disagrees with member slot union
```

## 5. 真实验证

| 检查 | 结果 |
|---|---|
| Racket full suite（含新 compiler oracle） | 通过 |
| Rust `cargo check` 与 release build | 通过 |
| 真实 Settings Form X11/Vulkan 回归 | 通过 |
| 真实鼠标 Apply All / Reset All composite oracle | 通过 |
| Scalar/reference packet differential | 继续通过 |
| 篡改 Scene 的启动期拒绝 | 通过 |

真实鼠标 oracle 点击编译器 Event Map 固定坐标 `Apply All=[46,226)×[344,356)` 与 `Reset All=[320,500)×[344,356)`。每个 transaction activation 都观察到 **一次** renderer request 和 **一次** packet activity compute dispatch：

```text
coalesced-batch composite-worklist:
  batch=coalesced-activate-apply-all-button
  slot=7 members=[3, 4, 5] packets=[3, 6, 9]
render-request-enqueue coalesced-activate-apply-all-button: ... worklist=7
packet-activity-dispatch worklist=batch-coalesced-activate-apply-all-button
  index=7 packets=[3, 6, 9] workgroups=3
```

同一实验对 `reset-all` 使用 slot 8 并得到相同的单 dispatch 结构。

## 6. 性能结果与边界

当前 Settings 事务在 composite lowering 前已经有一个 transaction-local union slot 6，因此它本来就执行一次 compute dispatch。故本实验**不能诚实地宣称**在这个特殊场景里 dispatch 数从 3 降为 1；实际完成的是把“已有 union 的语义”从 runtime selection policy 固化为 batch-local compiler proof。

当前 wgpu timestamp benchmark（llvmpipe Vulkan）证明 composite slots 进入了真实性能路径：

| Batch | CPU event-to-submit | GPU timestamp | Contract |
|---|---:|---:|---|
| Apply All, slot 7 | 211.1 µs | 741.6 µs | match |
| Reset All, slot 8 | 101.6 µs | 612.8 µs | match |

这两个单次值不可用于主张提速。要量化真正的“3 dispatch → 1 dispatch”收益，下一个实验必须构造一个 batch 中有多个**独立 task-local renderer request**、且此前没有 transaction-local union 的场景，并在同一 GPU 上采样 baseline 与 composite 版本。该实验现在不需要新增运行时依赖解析，只需利用本次已完成的 compiler proof ABI。

## 7. 可复现命令

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host
tools/verify_composite_worklists.sh

DISPLAY=:99 XDG_RUNTIME_DIR=/tmp WGPU_BACKEND=vulkan \
  wgpu-verify/target/release/noir_winit_host \
  out/settings-dashboard.scene.json \
  --benchmark-report wgpu-verify/out/composite-worklist-benchmark.json
```

## 8. 下一步

最值得继续的黑魔法是 **composite batch fusion**。在当前 `RenderRequest` FIFO 队列中，若连续请求具有 compiler-proved compatible composite coverage，编译器可为 batch产生单个 render request、单次 queue submit 和单个 dynamic-offset compute pass，同时保留每个 winner write 的独立 byte-range proof。完成该场景后，才可进行严格的 dispatch-count 和 CPU-submit 对照基准。
