# Noir Rust Strategy Dispatcher

**作者：Manus AI**  
**范围：** Rust 1.75、wgpu 0.20、winit 0.29.15 X11-only。  
**目标：** 让 host 消费 Racket compiler 固定的 `strategy_id` 和 `selection_proof`，在启动期验证 proof 后将其压缩为一个 Rust enum；事件期只按该 enum 分派 renderer，不读取 profile 文件、不比较 candidate costs、不进行 runtime strategy selection。

> Profile 的读取和成本选择发生在 Racket 宏展开期。Rust host 的职责是验证 compiler 声称的 winner 仍然符合 Scene 中携带的 proof，然后无解释地执行该 winner。

## 1. Scene ABI

`FrameCoalescedBatch` 新增三个 JSON 字段：

```rust
#[derive(Clone, Debug, Deserialize)]
struct FrameCoalescedBatch {
    id: String,
    task_ids: Vec<String>,
    execution_order: Vec<String>,
    winner_writes: Vec<FrameCoalescedWrite>,
    eliminated_writes: Vec<FrameCoalescedElimination>,
    merged_tile_ids: Vec<usize>,
    conflict_edges: Vec<BatchConflictEdge>,
    strategy_id: String,
    candidate_costs: HashMap<String, f64>,
    selection_proof: Option<StrategySelectionProof>,
}
```

`StrategySelectionProof` 只包含 compiler 已冻结的 profile ID、semantic group、metric、source batch、winner 与 stable tie-break order。它不包含 registry path，也不提供 host 可据以重新寻找或匹配 profile 的 adapter/vendor/driver 查询入口。

## 2. 启动期 proof 验证

`compiler_strategy_for_batch` 仅处理三种 compiler 允许的完整视觉路径：

| `strategy_id` | executor | 语义 |
|---|---|---|
| `full-redraw` | 整 canvas pass，绘制全部 quads 和全部 glyph packets | 完整 activate |
| `packet-aware` | 全部 compiler tiles，但只提交各 tile 的 `glyph_packet_ranges` | 完整 activate |
| `coalesced` | `merged_tile_ids`，提交局部 draw ranges 与 glyph subranges | 完整 activate |

完整 activate 的 `profile-guided` proof 必须同时满足以下条件：

| 防线 | 验证 |
|---|---|
| semantic group | 精确为 `complete-activate-v1` |
| metric | 精确为 `gpu_median_ns` |
| source/winner | 分别等于 batch ID 与 `strategy_id` |
| tie-break | 精确为 `[full-redraw, packet-aware, coalesced]` |
| candidate set | 恰好有 full、packet、coalesced 三项 |
| 禁止候选 | `action-aware` 不得出现 |
| winner cost | `strategy_id` cost 必须有限、非负且不大于每一候选 cost |

这不是第二套成本模型。host 不知道 adapter profile 的任何成本来源，也不排序候选；它仅确认 compiler JSON 内已固定的 winner 与其 proof 自洽。proof 通过后，`strategy_id` 被解析成：

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CompilerStrategy { FullRedraw, PacketAware, Coalesced }
```

并存入 `CompiledBatch.strategy`。事件期不保留 candidate cost map 的使用路径。

## 3. 事件期固定分派

Pointer-up 的有效 activate 现在调用：

```rust
let batch_id = self.event_batch_ids[index].activate.clone();
self.dispatch_compiler_batch(&batch_id);
```

`dispatch_compiler_batch` 先调用同一个 `apply_compiler_batch_writes`，因此无论 renderer strategy 是什么，release 的 button fields、action 的 state write、glyph ID patch 或 progress `size.x` patch 都沿用 compiler 的 `winner_writes`。随后只读取启动期枚举：

```rust
match batch.strategy {
    CompilerStrategy::Coalesced => self.mark_dirty_tiles(batch.tile_mask, &batch.id),
    CompilerStrategy::FullRedraw | CompilerStrategy::PacketAware => {
        self.pending_strategy = Some(batch.strategy);
        self.dirty_tiles = 0;
        self.canvas_dirty = true;
    }
}
```

在 `present()` 中，单次 `pending_strategy.take()` 决定 executor。`FullRedraw` 调用整 canvas renderer；`PacketAware` 使用 compiler 全 schedule mask 与既有 `glyph_packet_ranges`；`Coalesced` 使用 merged tile mask。没有 profile I/O、HashMap cost lookup、candidate comparison、sort、damage union 或几何相交计算。

Press、hover、release-only cancelled click 不属于完整 activate strategy set，仍沿用 compiler 固定的 transient tile mask 与 coalesced winner semantics。

## 4. 真实验证

### 4.1 真实 profile winner

用 `out/profile-strategy.scene.json` 进行 Vulkan/llvmpipe、Xvfb、真实 winit surface、X11 `xdotool` 三按钮点击。启动期日志依次确认三个 `profile-guided` proof：

```text
compiler strategy proof: batch=coalesced-activate-refresh-fps-button \
  profile=noir-vulkan-gpu-matrix-v1 strategy=coalesced metric=gpu_median_ns
```

FPS click 的 runtime 证据为：

```text
compiler strategy dispatch: batch=coalesced-activate-refresh-fps-button strategy=coalesced
glyph-id-patch fps: [800..804), [832..836), [864..868) (12 bytes)
tile-select ... mask=0x0000000000000009
tile-glyph-draw tile=0 packet=1 page=0 placements=[25..28) count=3 dynamic=true
```

Latency 对应 `[896..900)`、`[928..932)`、`[960..964)`；progress 保持 `[316..320)` 的 4-byte patch 并提交 0 glyph instances。

### 4.2 全三 executor 分支

`tools/make-strategy-dispatch-fixture.js` 是**受控 proof fixture**生成器，不是性能 profile generator。它保持 compiler 生成的 state/write/tile/placement ABI，只替换 synthetic、严格有序的 candidate costs 来迫使指定 winner。`tools/verify_strategy_dispatcher_branches.sh` 用真实 X11 FPS 点击分别验证：

| Fixture winner | 必须出现的日志 | 结果 |
|---|---|---|
| `full-redraw` | `compiler strategy dispatch ... full-redraw`；`strategy-executor full-redraw` | 通过 |
| `packet-aware` | `compiler strategy dispatch ... packet-aware`；`strategy-executor packet-aware`；mask `0x3f` | 通过 |
| registry `coalesced` | `compiler strategy dispatch ... coalesced`；mask `0x09`；placements `25..28` | 通过 |

fixture 的价值是证明 host 不会把 `coalesced` 硬编码成唯一路径，且不会重新根据自己的成本偏好覆盖 compiler winner。它不改变或伪造 registry 的真实性能结论。

## 5. 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui/wgpu-verify
cargo build --release --bin noir_winit_host

cd ..
./tools/verify_winit_host.sh out/profile-strategy.scene.json
./tools/verify_strategy_dispatcher_branches.sh out/profile-strategy.scene.json
```

## 6. 边界与后续

本阶段完成了 compiler choice 到 host executor 的闭环，但 `full-redraw` 和 `packet-aware` fixture 是为了验证分派 correctness，不应取代真实 Replay Matrix profile 的校准数据。下一阶段可让 Replay Matrix 在同一 host 中增加 `compiler-selected` row，验证真实 profile winner 与 dispatcher 的实际 work metrics/timestamp 一致；之后再在物理 Vulkan GPU 上冻结新的 registry entry。 
