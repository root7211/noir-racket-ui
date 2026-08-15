# Noir 真实 GPU 性能测量指南

本项目的现有 llvmpipe/Vulkan 结果用于验证 compiler proof、局部写入范围、命令数削减与回归协议。它们**不是**物理GPU吞吐、input-to-present或Noir与GPUI的最终排名。请在真实GPU机器上按本指南重新采样，并为每个adapter/driver单独保存profile。

> 不要给真实GPU强制设置 `WGPU_BACKEND=vulkan` 以外的适配器选择变量，也不要将 `llvmpipe` registry 中的系数复制给真实GPU。`profiles/registry.json` 当前只匹配 `llvmpipe (LLVM 20.1.2, 256 bits)` / Vulkan / 640×360。

## 1. 环境记录

开始前，请把以下信息与原始JSONL一同保存：GPU name、vendor/device ID、driver与Vulkan版本、CPU、kernel、发行版、分辨率/scale、桌面会话、刷新率、present mode、Racket/Rust/wgpu版本和git revision。

| 目标 | 建议 |
|---|---|
| 适配器 | 至少记录一块目标部署GPU；研究对照最好覆盖AMD、NVIDIA、Intel。 |
| 后端 | 优先使用Vulkan；确认日志中的adapter不是llvmpipe/lavapipe。 |
| 构建 | release；Noir主线维持Rust 1.75约束。GPUI comparator使用其独立新stable工具链。 |
| 预热 | 校准至少20次；每个正式workload至少200有效样本，分至少3个独立session。 |
| 采样顺序 | Noir/GPUI按交替顺序运行，避免温度、频率和cache漂移偏向一方。 |

## 2. 构建与正确性基线

```bash
cd noir-racket-ui

# Racket compiler/oracle
PLTCOLLECTS="$PWD:" racket tests/run.rkt

# 导出当前10,000行 list + scrollbar + navigation fixture
NOIR_ENTRY_MODULE=examples/data-register-table-10000.rkt \
  PLTCOLLECTS="$PWD:" \
  racket tools/export-dashboard.rkt out/data-register-table-10000.scene.json

# Rust/wgpu host
cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host

# 不要求物理显示时，可验证所有已冻结的Scene ABI与X11输入路径
./tools/verify_frozen_list_abi.sh
./tools/verify_row_activation.sh
./tools/verify_scrollbar_plan.sh
./tools/verify_list_navigation_plan.sh
```

这些oracle验证语义和GPU写入范围，**不**测量真实显示延迟。若只需GPU command-region/CPU submit基准，可以使用Xvfb；若测量桌面交互或input-to-present，必须使用真实显示器和目标compositor。

## 3. GPU command-region 与 host-path 基准

下例采集固定coalesced batch的真实GPU timestamp region和CPU event-to-submit。GPU timestamp不是present latency；CPU event-to-submit不包含timestamp readback等待。

```bash
# 使用真实硬件Vulkan adapter；不要把软件adapter当成结果。
export WGPU_BACKEND=vulkan
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

./wgpu-verify/target/release/noir_winit_host \
  out/data-register-table-10000.scene.json \
  --benchmark-report out/real-gpu-wgpu-benchmark.json

node tools/check-benchmark-report.js out/real-gpu-wgpu-benchmark.json
```

对fusion的多轮对照，先导出对应Scene，再采集原始JSONL：

```bash
PLTCOLLECTS="$PWD:" NOIR_ENTRY_MODULE=examples/composite-worklist-dashboard.rkt \
  racket tools/export-dashboard.rkt out/composite-worklist-dashboard.scene.json

./tools/sample_fusion_benchmark.sh \
  ./wgpu-verify/target/release/noir_winit_host \
  out/composite-worklist-dashboard.scene.json \
  200 out/real-gpu-fusion-samples.jsonl

python3 tools/summarize_fusion_benchmark_samples.py \
  out/real-gpu-fusion-samples.jsonl \
  out/real-gpu-fusion-summary.json
```

将`adapter_name`、driver版本、timestamp period、workload fingerprint与原始JSONL一起保存；不同adapter或分辨率的结果不能合并为一个profile。

## 4. 长列表与GPUI对照

当前Noir与GPUI脚本的共同指标是外部X11输入至语义endpoint（handler或viewport日志）；它**排除GPU present**。它可用于检查语义等价和系统级尾部噪声，不可作为GPU帧时间。

```bash
# GPUI独立工具链；首次需按项目README安装所需依赖。
RUSTUP_HOME="$HOME/.rustup-gpui" \
CARGO_HOME="$HOME/.cargo-gpui" \
  "$HOME/.cargo-gpui/bin/cargo" build --release \
  --manifest-path gpui-virtual-list-benchmark/Cargo.toml

# 先用15轮复现旧协议；正式发布改为200轮、多session、交替顺序。
./tools/sample_noir_gpui_virtual_list_input.sh 15 25
./tools/sample_noir_gpui_virtual_list_scroll.sh 15

python3 tools/summarize_noir_gpui_virtual_list_input.py \
  wgpu-verify/out/noir-gpui-virtual-list-input-samples.jsonl \
  wgpu-verify/out/noir-gpui-virtual-list-input-summary.json
python3 tools/summarize_noir_gpui_virtual_list_scroll.py \
  wgpu-verify/out/noir-gpui-virtual-list-scroll-samples.jsonl \
  wgpu-verify/out/noir-gpui-virtual-list-scroll-summary.json
```

公平性条件是：相同物理GPU、backend、窗口系统、分辨率、scale、字体、文本、逻辑数据、输入序列、预热状态和语义终态。若GPUI不能给出相同边界的GPU timestamps，则只比较公共的端到端语义指标；不要把Noir内部timestamp与GPUI handler日志混为同一种度量。

## 5. 真实GPU profile提交模板

请为每个物理adapter建立独立profile，而不是改写llvmpipe样本。推荐提交以下内容：

```text
profiles/<vendor>-<device>-<driver>-vulkan.json
out/<device>-calibration-matrix.jsonl
out/<device>-replay-matrix.json
out/<device>-manifest.json
out/<device>-fusion-samples.jsonl
out/<device>-list-samples.jsonl
BENCHMARKS/<device>-environment.md
```

每份结论都必须标注测量边界：`CPU event-to-submit`、`GPU command region`、`X11 endpoint excluding present`或`input-to-photon`。只有最后一类经过物理显示测量，才能用于用户感知延迟结论。

## 6. 发布前检查

```bash
# 适配器必须不是软件适配器。
grep -E 'adapter|llvmpipe|lavapipe' out/real-gpu-wgpu-benchmark.json

# 结构contract必须一致。
node tools/check-benchmark-report.js out/real-gpu-wgpu-benchmark.json

# 查看当前llvmpipe证据与真实GPU修正原则。
less LLVMPipe_VULKAN_PERFORMANCE_INTERPRETATION.md
```

如果输出出现`llvmpipe`或`lavapipe`，该运行仍是软件适配器验证，不应标记为真实GPU测量。
