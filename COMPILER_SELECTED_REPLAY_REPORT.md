# Noir Compiler-Selected Replay 与自一致 Oracle

**作者：Manus AI**  
**范围：** Rust 1.75、wgpu 0.20、Vulkan/llvmpipe、winit X11 host。  
**目标：** 让 Replay Matrix 不仅能手动指定 renderer mode，还能直接执行 Racket compiler 已冻结的 `strategy_id`，并在每个采样中证明 profile proof、host executor、winner writes、tile/glyph submission 和 timestamp 记录彼此一致。

> `compiler-selected` 不在运行时比较 replay costs。它读取的是 host 启动期已经验证并压缩的 `CompiledBatch.strategy`；Replay 只测量该固定策略的实际执行后果。

## 1. 新增第五种 Replay Mode

原有矩阵包含 `full-redraw`、`packet-aware`、`action-aware` 与 `coalesced`。现新增：

```rust
enum ReplayMode {
    FullRedraw,
    PacketAware,
    ActionAware,
    Coalesced,
    CompilerSelected,
}
```

前四个 mode 用于控制实验变量。`CompilerSelected` 则是对真实发布路径的测量：它从 `CompiledBatch.strategy` 获取启动期验证后的 enum，调用同一份 batch winner write 路径，再由该 enum 选择 full canvas、all-schedule packet-aware 或 merged-tile coalesced renderer。

| strategy enum | compiler-selected executor | expected visual语义 |
|---|---|---|
| `FullRedraw` | full canvas / all packets | 完整 activate |
| `PacketAware` | all compiler tiles / glyph packet ranges | 完整 activate |
| `Coalesced` | batch merged tile mask / local packet ranges | 完整 activate |

`action-aware` 不属于完整 activate 的语义等价组，因此不会成为 `CompilerSelected` 的合法 executor。

## 2. 单次采样的自一致合约

`compiler_selected_once` 每次先复位 compiler initial state、instance buffer 和 glyph buffer。它读取已验证 batch 的 `strategy` 与原始 Scene proof，得到：

1. expected winner write bytes；
2. expected tile mask；
3. expected tile、glyph draw 与 glyph instance count；
4. fixed strategy executor；
5. GPU timestamp 与 CPU event-to-submit sample。

随后在一个完整 batch 中应用 release/action winner writes，并执行对应 renderer。每个 sample 生成：

```rust
struct CompilerSelectedConsistency {
    compiler_strategy_id: String,
    proof_profile_id: String,
    proof_winner: String,
    actual_executor: String,
    expected_tile_mask_hex: String,
    observed_tile_mask_hex: String,
    expected_tile_count: usize,
    observed_tile_count: usize,
    expected_glyph_draw_count: usize,
    observed_glyph_draw_count: usize,
    expected_glyph_instance_count: u32,
    observed_glyph_instance_count: u32,
    expected_winner_write_bytes: usize,
    observed_winner_write_bytes: usize,
    self_consistent: bool,
}
```

`self_consistent` 只有在 proof winner 等于 fixed strategy、实际 executor 等于 fixed strategy、observed mask 等于 expected mask、所有 tile/glyph metrics 相等、以及 winner write bytes 相等时才为真。任一不一致立即令 benchmark 失败；报告不会生成一个“看似成功”的漂移结果。

## 3. 报告 ABI v2

Replay JSON 升级为 `noir-wgpu-replay-matrix-v2`，每个完整 activate workload 有五行，总计 15 行。常规四种 mode 的 report 行保持工作量和统计字段；`compiler-selected` 额外携带 `compiler_selected` 自一致对象。

JSON oracle 不仅检查 schema、GPU timestamp、样本分位数和 15 条 workload×mode 记录，还检查：

| 不变量 | 要求 |
|---|---|
| profile winner | 当前 registry 为 `coalesced` |
| actual executor | 与 `compiler_strategy_id` 同为 `coalesced` |
| FPS tile mask | `0x0000000000000009` |
| latency tile mask | `0x0000000000000012` |
| progress tile mask | `0x0000000000000024` |
| metrics glyph work | 1 draw / 3 instances |
| progress glyph work | 0 draw / 0 instances |
| winner bytes | metrics 36 bytes；progress 28 bytes |
| self consistency | 每条 compiler-selected row 必须为 `true` |

## 4. 真实 Vulkan/X11 结果

以 `out/profile-strategy.scene.json` 在 Xvfb Surface、Vulkan/llvmpipe 上运行，timestamp period 为 `1.0 ns`，warm-up `1` 次、采样 `3` 次。所有三条 compiler-selected row 都选择并实际执行 `coalesced`。

| Workload | compiler-selected GPU median | CPU event→submit median | Tile / glyph instances | Winner bytes | Self-consistent |
|---|---:|---:|---:|---:|---:|
| progress activate | 327,034 ns | 109,524 ns | 2 / 0 | 28 | true |
| FPS activate | 516,237 ns | 180,129 ns | 2 / 3 | 36 | true |
| latency activate | 284,444 ns | 161,796 ns | 2 / 3 | 36 | true |

这些数值证明的是 compiler-selected pipeline 的真实执行闭环，而不是新的 profile calibration。样本量为 3，且 backend 是 llvmpipe；因此它适合作为功能/协议自一致性证据和 CI 阈值基线，不能被解释为物理 GPU 的稳定性能估计。真实 profile 更新仍须采用物理 Vulkan GPU、较长 warm-up 与至少 200 样本的独立测量。

## 5. 运行与验证

```bash
cd /home/ubuntu/noir_review/noir-racket-ui/wgpu-verify
cargo build --release --bin noir_winit_host

cd ..
# 在已启动的 X11/Xvfb Vulkan 环境下执行。
./wgpu-verify/target/release/noir_winit_host \
  out/profile-strategy.scene.json \
  --replay-matrix out/compiler-selected-replay-matrix.json \
  --warmup 1 --samples 3

node tools/check-replay-matrix.js out/compiler-selected-replay-matrix.json
```

`tools/verify_winit_host.sh out/profile-strategy.scene.json` 继续验证真实 pointer-down/pointer-up 分派；`tools/verify_strategy_dispatcher_branches.sh` 则验证 full-redraw 与 packet-aware fixture branch。三类验证分别覆盖交互、分派正确性与 compiler-selected measurement。

## 6. 后续边界

现在 compiler profile selection、Rust proof validation、strategy dispatcher、winner-only patch、tile/packet culling 和 timestamp report 已形成闭环。下一阶段应将 v2 report 纳入**profile freshness gate**：以 profile cost 的相对偏差、P95 与 adapter identity 为输入，生成 stale-profile 诊断，但绝不在运行时改写 strategy 或自动污染 registry。 
