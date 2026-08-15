# Noir Racket Profile Admission：Freshness 驱动的编译期准入

**作者：Manus AI**  
**范围：** `#lang noir/ui` 宏展开期、Rust 离线 Calibration Manifest/Freshness Gate、wgpu X11 host。  
**目标：** 确保已经 stale、inconclusive、错配或缺失的 calibration 证据不会静默参与 Racket 的 replay-cost `strategy_id` lowering。

> Runtime host 只验证 Scene proof 并执行策略；只有 Racket 宏展开期能够接受或拒绝 profile admission。不会在窗口事件、GPU 提交或 Rust dispatcher 内重新评估 Freshness。

## 1. 输入与环境契约

Racket Profile Admission 读取以下**离线**输入：

| 环境变量 | 作用 |
|---|---|
| `NOIR_COST_PROFILE` | profile registry 路径 |
| `NOIR_PROFILE_ID` | 要求的冻结 profile |
| `NOIR_PROFILE_ADMISSION` | `strict` 或 `permissive` |
| `NOIR_FRESHNESS_MANIFEST` | Rust 生成的 `noir-calibration-manifest-v1` |
| `NOIR_FRESHNESS_DIAGNOSTIC` | Rust 输出的 `noir-profile-freshness-v1` |
| `NOIR_FRESHNESS_SCENE_FINGERPRINT` | 构建器显式提供的 Scene build fingerprint |

宏展开期依次验证 manifest schema、diagnostic schema、manifest profile ID、diagnostic status、expected Scene fingerprint 以及 activate batch 的 manifest strategy。缺失任何 artifact、status 不是 `fresh`、profile ID 不同、Scene fingerprint 不同、或 manifest 未覆盖 compiler winner，都会拒绝或退化；不会把不完整证据视为 fresh。

Scene fingerprint 是一个显式构建输入，而不是尝试让输出 JSON 对自身做循环 hash。它代表被 calibration 的 build/source identity，避免把某一 Scene 的 calibration artifact 错接给另一个 build。当前 Rust artifact 使用 FNV-1a-64 作为 CI/研究原型 identity；这不是密码学签名。

## 2. 两种 Policy

| Policy | Fresh、profile/manifest winner 一致 | stale/inconclusive/missing/错配 |
|---|---|---|
| `strict` | 允许 `profile-guided` replay costs | 宏展开期 `raise-syntax-error`，不输出 Scene |
| `permissive` | 允许 `profile-guided` replay costs | 输出保守 `coalesced`，proof 标明 `profile-unavailable` 与 admission 原因 |

`permissive` fallback 的选择不是新的 cost decision。它只使用既有 Rust 已允许的 `profile-unavailable → coalesced` ABI，因此 host 会继续执行固定 executor；不会查 profile、比较 cost 或在运行时自适应。

## 3. Macro Lowering

`compile-profile-guided-batch-strategies` 先按 registry 的 `full-redraw`、`packet-aware`、`coalesced` 同语义候选得到稳定 tie-break winner。随后调用 admission gate：

```racket
(if (admit-replay-winner proposed winner root)
    proposed
    (admission-fallback proposed admission-reason))
```

严格准入不能通过时，宏在 Scene 产生前终止。宽松准入不能通过时，activate batch 被冻结为：

```text
strategy_id       = coalesced
candidate_costs   = { coalesced: 0.0 }
proof.mode        = profile-unavailable
proof.reason      = freshness-not-fresh
proof.policy      = permissive
proof.status      = stale | inconclusive | missing | invalid
```

fresh strict Scene 仍使用已有 host-compatible proof：

```text
proof.mode        = profile-guided
proof.semantic    = complete-activate-v1
proof.metric      = gpu_median_ns
proof.winner      = coalesced
proof.tie-break   = [full-redraw, packet-aware, coalesced]
```

因此无需给 Rust dispatcher 新增动态分支；Rust 已有 proof validator 可直接验证这两种 mode。

## 4. 实际验证

使用现有 llvmpipe calibration artifact：

| 项目 | 值 |
|---|---|
| profile | `noir-vulkan-gpu-matrix-v1` |
| admission build fingerprint | `fnv1a64:b9abfd758142e4cc` |
| fresh diagnostic | `out/freshness-fresh.json` |
| stale diagnostic | `out/freshness-stale.json` |
| full semantic candidates | full-redraw、packet-aware、coalesced |
| admitted winner | coalesced |

一键 oracle `tools/verify_profile_admission.sh` 验证三条路径：

1. **strict + fresh**：生成 Scene；三个 activate batch 使用 `profile-guided` proof，candidate costs 仅包含 full/packet/coalesced。
2. **strict + stale**：Racket 宏展开以 `strict Profile Admission rejected` 失败；不会生成带不可信 profile cost 的 Scene。
3. **permissive + stale**：生成 Scene，但三个 activate batch 固定为 `profile-unavailable → coalesced`，proof 中记录 `freshness-not-fresh`、`permissive` 和 `stale`。

随后把 strict fresh Scene 送入真实 Vulkan/llvmpipe、Xvfb、winit X11 输入闭环。Rust startup proof validation 成功；FPS 仍以 12-byte glyph patch 和 tile mask `0x09` 提交 3 glyph instances，latency 使用 `0x12`，progress 保持 4-byte instance patch 且无 glyph draw。Admission 只改变编译期 profile 准入，没有改变已经验证的 runtime 最短路径。

## 5. 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
./tools/verify_profile_admission.sh

# 可选：验证 strict fresh Scene 的真实 X11 host 兼容性。
./tools/verify_winit_host.sh out/profile-admission-strict-fresh.scene.json
```

在正式物理 GPU pipeline 中，构建器应使用同一 build/source fingerprint 生成 calibration artifact 和 strict compilation。若 artifact、driver、Scene 或 profile 发生变化，应先运行 Rust Freshness Gate；strict policy 会拒绝，permissive policy 会明确退化，而不是静默沿用旧策略。 
