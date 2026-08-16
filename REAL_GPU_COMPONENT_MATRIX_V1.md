# Noir Real-GPU Component Matrix v1

**状态：** 可执行测量协议；当前CI沙箱因仅暴露 llvmpipe CPU Vulkan adapter 而被刻意拒绝，不产生或解释伪“真实GPU”数值。

## 目的

该协议测量当前 Noir 编译器对两类 Material 组件 Scene 所导出的 **compiler-selected** 渲染工作负载：带 navigation selection 和静态 icon placement 的 dashboard，以及带 dialog/menu、shadow、icon 和 finite release motion 的 overlay。每个结果行都同时报告 GPU timestamp 的时延分布、CPU event-to-submit 分布、固定 tile 范围、glyph draw 数和 winner write 字节数。

> 该矩阵是 Noir 自身组件路径的真实性能测量；它不是 GPUI、Flutter、Qt 或任何其他框架的比较声明。跨框架输入延迟对照仍使用独立的配对、随机区组协议。

## 真实硬件准入

运行器在执行前读取 `vulkaninfo --summary`。出现 `llvmpipe`、`lavapipe`、CPU device type 或没有Vulkan物理设备时，会以退出码 `42` 或 `43` 终止。每份 replay matrix 还要求 wgpu 时间戳查询可用、adapter 名称非CPU软件实现、以及每个 compiler-selected row 的 self-consistency proof 为真。

| 项目 | 默认值 | 含义 |
|---|---:|---|
| 会话数 | 5 | 独立采样会话数。 |
| warm-up | 25 | 每个 replay row 的预热迭代数。 |
| samples | 100 | 每个 replay row 的GPU/CPU采样数。 |
| 固定Scene | 2 | `material-profile-dashboard` 和 `material-overlay-showcase`。 |
| renderer mode | compiler-selected | 只报告由编译器 proof 选择且自一致的执行器。 |

## 在真实GPU机器上运行

在克隆仓库的根目录执行以下命令。运行器默认使用现有的硬件X11/WSLg `DISPLAY`；若已确认 Xvfb 仍通过硬件Vulkan设备，可显式设置 `USE_XVFB=1`。

```bash
./tools/run_real_gpu_component_matrix_v1.sh
```

可通过环境变量缩短试运行或指定输出目录：

```bash
SESSIONS=2 WARMUP=5 SAMPLES=20 \
OUT_ROOT=data/material-component-gpu-smoke \
./tools/run_real_gpu_component_matrix_v1.sh
```

运行完成后，输出目录包含每个 session 的 dashboard/overlay replay matrix、宿主日志、Vulkan adapter 摘要、运行manifest、结构化汇总、Markdown表格和 `component-gpu-median.png`。建议先执行 smoke run 检查硬件与时间戳门禁，再使用默认参数执行正式测量。

## 结果解释

`component-gpu-summary.md` 的 GPU 指标是“各session中位数的中位数”，尾部指标为“各session P95 的95分位”；它们避免将单个session内的大量高度相关样本误写为独立硬件试验。任何跨机器、驱动、功耗状态或adapter不同的结果均不应直接合并。

跨框架比较必须额外固定同一显示后端、窗口尺寸、工作负载语义、输入批量、热身、随机区组顺序和完整性阈值，并使用 `tools/rigorous_benchmark.sh` 与 `tools/analyze_rigorous_benchmark.py` 的配对分析路径。旧脚本的硬件信息不可自动代表本次提交；每轮必须重新记录新commit和二进制哈希。
