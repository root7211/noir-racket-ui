# Noir Canonical Build Input 与自动 Source Fingerprint

**作者：Manus AI**  
**范围：** Racket `tools/export-dashboard.rkt`、`#lang noir/ui` 宏展开、Rust/wgpu Calibration Manifest、Freshness Gate 与 strict Profile Admission。  
**目标：** 让 calibration evidence 自动绑定到真实编译输入，消除 `NOIR_FRESHNESS_SCENE_FINGERPRINT` 的人工传递。

> Source fingerprint 是可复现构建 identity，不是输出 Scene JSON 的自指 hash。Racket 计算它，Rust 保存和诊断它，Racket strict admission 自动比较它；窗口事件期永远不读取该 artifact。

## 1. Canonical Build Input v1

`tools/export-dashboard.rkt` 在动态加载 `dashboard.rkt` 前构造一个**有序 list**，再以其 `~s` representation 的 UTF-8 bytes 计算 64-bit FNV-1a。排序问题不会进入 hash，因为输入是 ordered list 而不是 JSON hash object。

| Canonical 输入 | 绑定的变化 |
|---|---|
| `schema` | Canonical Build Input ABI 变化 |
| `compiler_abi`、`scene_json_abi` | lowering/Scene contract 变化 |
| target width/height、Quad/Glyph ABI bytes | GPU target 或 buffer ABI 变化 |
| `dashboard.rkt` raw bytes FNV | DSL/静态 UI 定义变化 |
| `noir/ui/main.rkt` raw bytes FNV | macro/compiler 变化 |
| `tools/export-dashboard.rkt` raw bytes FNV | builder/attestation 逻辑变化 |
| target profile ID 与 registry raw bytes FNV | device cost profile/registry 变化 |

`NOIR_PROFILE_ADMISSION` 刻意**不参与** source identity。它是同一 source build 的准入行为：同一 build 可以通过 `bootstrap` 生成首个 calibration artifact，再由 `strict` 使用相同 source identity 接受该 artifact。policy 仍写入 attestation 和 batch proof 作为审计元数据。

## 2. Scene Attestation ABI

构建器动态 require `dashboard.rkt` 前，把计算出的 fingerprint 放入一个 parameterized environment 的 `NOIR_CANONICAL_SOURCE_FINGERPRINT`。因此 Racket Profile Admission 在 macro expansion 时无需用户手工设定 fingerprint。Scene JSON 增加独立、后向兼容的顶层对象：

```json
"build_attestation": {
  "schema": "noir-build-attestation-v1",
  "source_fingerprint_fnv1a64": "fnv1a64:…",
  "compiler_abi": "noir-racket-ui-abi-v2",
  "scene_json_abi": "noir-scene-json-v2",
  "target": { "width": 640, "height": 360,
               "quad_instance_bytes": 48, "glyph_cell_bytes": 32 },
  "profile_id": "noir-vulkan-gpu-matrix-v1",
  "profile_admission": "strict|permissive|bootstrap",
  "canonical_input": { "dashboard_source": "fnv1a64:…", "compiler_source": "fnv1a64:…",
                         "builder_source": "fnv1a64:…", "profile_registry": "fnv1a64:…" }
}
```

runtime Scene IR 本身未增加 field；非 builder 的直接 `write-scene-json` 调用保持不带 attestation 的 legacy JSON，以便独立 DSL test 保持可用。

## 3. Bootstrap 与 Source-Aware Freshness

首次 calibration 面临一个正常的 bootstrap 问题：strict policy 需要 fresh artifact，但 fresh artifact 又需要一个可以运行完整 `profile-guided` strategy 的 Scene。为此 `NOIR_PROFILE_ADMISSION=bootstrap` 只用于**离线 calibration 构建**。它输出 profile-guided candidate/proof，同时在 proof 中明确写入 `admission_policy=bootstrap`。Rust 只把它作为 calibration provenance，不在交互期提升权限。

Rust host 解码 `build_attestation`，在 calibration manifest 增加：

| Manifest 字段 | 语义 |
|---|---|
| `scene_fingerprint_fnv1a64` | 被测 Scene 输出的 forensic hash |
| `source_fingerprint_fnv1a64` | strict admission 的身份键 |

Freshness Gate 现在比较当前 Scene attestation 的 `source_fingerprint_fnv1a64` 与 manifest 的 source fingerprint。它保留输出 Scene hash 为 `scene-output-fingerprint-informational`，但不将其作为 gate identity，因为 strict/proof metadata 可合法改变输出 JSON，而 canonical source/ABI contract 才是 calibration 的稳定对象。

## 4. 自动 strict 闭环

最终真实 artifact 使用 source fingerprint：

```text
fnv1a64:ee1f8a6c5dad8b1f
```

链路如下：

```text
bootstrap Racket build
  → build_attestation(source fingerprint)
  → Vulkan/Xvfb compiler-selected Replay Matrix
  → Rust Calibration Manifest(source fingerprint)
  → Rust source-aware Freshness Gate = fresh
  → strict Racket build（无手工 fingerprint 环境变量）
  → profile-guided Scene proof
  → Rust proof validation / coalesced dispatcher
```

自动 strict build 的三个 activate batch 都保留 `profile-guided` proof、`admission_policy=strict`、`freshness_status=fresh`。真实 X11 验证仍得到：FPS tile mask `0x09`、3 glyph instances、12-byte glyph patch；latency `0x12`；progress `0x24`、4-byte instance patch、零 glyph draw。

## 5. 可复现性与失败测试

`tools/verify_build_attestation.sh` 运行两个相同 strict build，要求 fingerprint 完全相同；然后复制 registry 并添加一个保持 JSON 有效的字节变化。因为 registry raw bytes 是 canonical input，source fingerprint 改变，旧 manifest 无法再通过 strict Profile Admission。脚本确认 compiler 以 `strict Profile Admission rejected` 失败。

`tools/check-build-attestation.js` 验证：bootstrap/strict Scene identity 相同、manifest identity 一致、freshness 的 `source-fingerprint` check 通过、输出 Scene hash 只是 informational check、strict activate batches 均为 profile-guided。

## 6. 边界

FNV-1a-64 在本研究原型中用于快速 CI identity 和误配检测，**不是**抗碰撞的签名。对外发布或多方 artifact exchange 应升级为 canonical JSON + SHA-256、签名、可信时间戳以及受控 profile registry lockfile。当前 raw registry bytes 对空白符也敏感；这是一种保守 fail-closed 设计。若未来希望语义等价的格式化不触发重新校准，应定义 registry canonical JSON encoding 后再计算加密 hash。 
