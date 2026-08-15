# Noir Calibration Manifest 与 Profile Freshness Gate

**作者：Manus AI**  
**范围：** Rust 1.75、wgpu 0.20、Vulkan/llvmpipe、winit X11 host。  
**目标：** 将 compiler-selected replay 的真实执行结果冻结成可追溯 Calibration Manifest，并在离线 gate 中判断该 calibration 与当前 Scene、设备 identity、Replay 报告和 profile 成本是否仍兼容。

> Freshness Gate 是诊断器，不是运行时策略控制器。它永远不会读取窗口事件、修改 `strategy_id`、改写 coalesced batch，也不会在 host 内重新比较成本来选择 executor。

## 1. Calibration Manifest ABI

`--replay-matrix` 已完成 compiler-selected v2 matrix 后，可追加：

```text
--calibration-manifest out/calibration-manifest.json
```

宿主从 Matrix 的三条 `compiler-selected` row 提取 proof 已验证的 actual executor、tile/glyph work contract 与 GPU timestamp 统计，并连同输入 identity 写入 `noir-calibration-manifest-v1`。

| 字段 | 作用 |
|---|---|
| `profile_id` | 绑定 compiler 选择 proof 所属的冻结 profile |
| `scene_fingerprint_fnv1a64` | 绑定被测 Scene JSON 的 FNV-1a-64 输入指纹 |
| `replay_report_fingerprint_fnv1a64` | 绑定 Replay Matrix v2 完整报告，防止 manifest 与 report 被错配 |
| adapter/backend/timestamp | 绑定实际 wgpu 测量环境与 timestamp period |
| warm-up/sample count | 明确 artifact 的采样质量 |
| `compiler_selected[]` | 每个完整 activate batch 的 fixed strategy、tile mask、work contract、GPU median/P95 |

本次真实 artifact 的关键 identity 如下：

| 项目 | 值 |
|---|---|
| Profile | `noir-vulkan-gpu-matrix-v1` |
| Scene FNV-1a-64 | `fnv1a64:b9abfd758142e4cc` |
| Replay report FNV-1a-64 | `fnv1a64:df189c98b5ad4016` |
| Adapter | `llvmpipe (LLVM 20.1.2, 256 bits)` |
| Backend | Vulkan |
| Timestamp period | 1.0 ns |
| Warm-up / samples | 2 / 5 |

## 2. Freshness Gate 策略

Gate 输入为 registry、manifest、当前 Scene JSON 与用于生成 manifest 的 Replay Matrix。它逐项检查：

1. manifest、registry 和 replay schema；
2. 当前 Scene fingerprint 与 manifest fingerprint；
3. replay report fingerprint、profile ID、adapter/backend、timestamp capability/period；
4. registry matcher 与当前校准 identity；
5. profile replay semantic group、metric 与 candidate work contract；
6. 每个 compiler-selected batch 的 strategy、tile/glyph/write metrics；
7. GPU median/P95 相对 profile frozen cost 的漂移；
8. manifest sample count 是否满足调用方设定的最小样本数。

漂移采用：

```text
abs(observed_ns - frozen_ns) / frozen_ns
```

| Status | 条件 | 含义 |
|---|---|---|
| `fresh` | identity/contract 完整匹配、样本充足、所有 median/P95 漂移不超过阈值 | artifact 可作为当前离线 profile 的兼容证据 |
| `stale` | identity、fingerprint、work contract 不匹配，或任一成本漂移越过阈值 | profile artifact 不应被当作当前环境的性能证据 |
| `inconclusive` | identity 与 contract 通过，但样本数不足最小门槛 | 尚不足以做 freshness 判断；不等于 profile 正确或错误 |

诊断 report 的 policy 始终为：

```text
diagnostic-only; runtime strategy_id is immutable
```

因此 stale 只会产生离线报告；窗口事件仍只执行 Scene 中已经冻结并由 startup proof 验证的 strategy。

## 3. 真实校准结果

通过真实 Xvfb/Vulkan/llvmpipe Surface 运行 Matrix，warm-up 2、samples 5 后生成 manifest。所有完整 activate batch 的 compiler-selected executor 都是 `coalesced`。

| Batch | Fixed strategy | Tile mask | Tile / glyph instances | Winner bytes | GPU median / P95 |
|---|---|---:|---:|---:|---:|
| progress activate | coalesced | `0x24` | 2 / 0 | 28 | 514,942 / 571,690 ns |
| FPS activate | coalesced | `0x09` | 2 / 3 | 36 | 413,001 / 525,353 ns |
| latency activate | coalesced | `0x12` | 2 / 3 | 36 | 449,238 / 1,595,555 ns |

这些统计显示 work contract 没有漂移：progress 仍为零 glyph draw；两个 metrics batch 都为一条 glyph draw、三个 glyph placement instance 和 36-byte winner writes。latency 的 P95 明显受 llvmpipe/CI 环境噪声影响，这正是 gate 保留 P95 比对、同时严格区分 calibration evidence 与真实物理 GPU profile 的原因。

## 4. 三分支验证

下列命令不创建窗口、不进入 dispatcher；它们只运行离线 Rust gate：

```bash
HOST=wgpu-verify/target/release/noir_winit_host
SCENE=out/profile-strategy.scene.json
REGISTRY=profiles/registry.json
MANIFEST=out/calibration-manifest.json
REPLAY=out/calibration-replay-v2.json

# 用宽阈值演示兼容 identity/contract 下的 fresh。
$HOST "$SCENE" --freshness-registry "$REGISTRY" \
  --freshness-manifest "$MANIFEST" --freshness-replay "$REPLAY" \
  --freshness-report out/freshness-fresh.json \
  --freshness-threshold 10.0 --freshness-min-samples 5

# 以零漂移阈值演示 stale；不改变 Scene strategy。
$HOST "$SCENE" --freshness-registry "$REGISTRY" \
  --freshness-manifest "$MANIFEST" --freshness-replay "$REPLAY" \
  --freshness-report out/freshness-stale.json \
  --freshness-threshold 0.0 --freshness-min-samples 5

# 要求 6 个样本演示 inconclusive。
$HOST "$SCENE" --freshness-registry "$REGISTRY" \
  --freshness-manifest "$MANIFEST" --freshness-replay "$REPLAY" \
  --freshness-report out/freshness-inconclusive.json \
  --freshness-threshold 10.0 --freshness-min-samples 6

node tools/check-freshness-gate.js "$MANIFEST" \
  out/freshness-fresh.json out/freshness-stale.json \
  out/freshness-inconclusive.json
```

JSON oracle 已确认 manifest 包含 3 个 compiler-selected cases、三种 report status 都正确、每条 case 维持 `coalesced` fixed strategy 且 work contract 匹配。`stale` case 的非零 drift 被记录而非被隐藏；`inconclusive` case 明确指出 minimum-samples check 未通过。

## 5. 设计边界与后续

本实现使用 FNV-1a-64 作为快速 artifact **identity** 指纹，适合研究原型、CI 和错配保护，但它不是加密完整性或供应链签名机制。若需对外发布 immutable calibration artifact，应增加 SHA-256、签名与可信时间戳。

llvmpipe artifact 仍应定位为协议/回归验证资料。正式 profile 更新应在物理 Vulkan GPU 上执行更大采样，例如 warm-up 20、samples 200，并将该 manifest、原始 matrix、adapter/driver identity 与 registry 更新作为单一 reviewable commit 提交。 
