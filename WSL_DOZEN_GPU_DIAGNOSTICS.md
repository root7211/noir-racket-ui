# WSL、Dozen 与 wgpu 30 物理 GPU 诊断

**目标不是让日志里出现 `Vulkan`，而是证明 Noir 使用的 wgpu 30 实际枚举到了物理适配器。**一个 `backend=Vulkan type=Cpu name="llvmpipe"` 结果仅说明Vulkan loader与软件ICD可用；它不能用于真实GPU性能测量。

> 在修改ICD覆盖、Mesa包或Windows驱动之前，先保存未强制设置环境变量的诊断报告。否则一次临时修复可能隐藏原本可用的原生Vulkan路径，或使问题从适配器选择变成loader配置问题。

## 1. 迁移后需要满足的版本边界

| 组件 | 当前主线 | 含义 |
|---|---:|---|
| Rust | `1.87.0` | `rust-toolchain.toml`固定；这是wgpu 30的MSRV。 |
| wgpu | `30.0.0` | Noir adapter probe、窗口宿主与基准共用同一后端版本。 |
| winit | `0.29.15`，仅X11 | 本次不引入Wayland变量。 |
| 历史基线 | tag `wgpu-0.20-rust-1.75-baseline` | 用于定位迁移差异，而非继续进行真实GPU测量。 |

wgpu 30可改善较新的Vulkan loader、Mesa或Windows/WSL驱动栈的API兼容性；但**它不会制造Windows GPU虚拟化设备、修复损坏的ICD JSON，也不会把CPU软件驱动变成物理GPU**。[1]

## 2. 首先运行只读诊断

在WSL发行版、仓库根目录执行：

```bash
git pull --ff-only
./tools/diagnose_wsl_vulkan.sh | tee out/wsl-wgpu30-diagnostics.txt
```

该脚本不会安装软件、不会设置永久环境变量，也不会覆盖ICD。它记录内核、WSL互操作标记、`/dev/dxg`、WSLg目录、Vulkan ICD清单、`vulkaninfo --summary`与两次wgu 30 adapter probe。

| Probe结果 | 含义 | 是否可做真实GPU基准 |
|---|---|---|
| `backend=Vulkan type=DiscreteGpu` 或 `IntegratedGpu` | wgpu 30已看到物理GPU。 | 可以；继续ABI回归与基准校准。 |
| 只有 `backend=Vulkan type=Cpu` / `llvmpipe` | Vulkan可用，但只有软件实现。 | 不可以。 |
| probe没有adapter | 先处理loader、ICD或WSL图形栈。 | 不可以。 |
| `/dev/dxg` 缺失 | WSL guest没有Windows GPU paravirtualization设备。 | 不可以；升级wgpu无效。 |

## 3. Dozen不是唯一正确路径

Dozen（`dzn`）是Mesa的Vulkan-on-D3D12路径，主要用于特定的WSL/Windows图形栈场景。它不是“只要安装就一定更快”的Noir要求，也不是所有硬件的首选ICD。若未强制环境的wgpu probe已经显示物理Vulkan adapter，应优先使用该原生路径；只有当报告显示`/dev/dxg`存在、但Vulkan-only probe仍只看到CPU适配器时，才把dzn/Mesa ICD与Windows驱动作为诊断对象。[2] [3]

建议按以下顺序排除，而不是直接设置`VK_ICD_FILENAMES`：

| 顺序 | 检查 | 正常证据 | 异常时的责任边界 |
|---:|---|---|---|
| 1 | Windows侧WSL与GPU驱动 | `wsl --update`完成；供应商WSL兼容驱动为当前版本。 | Windows主机驱动或WSL运行时。 |
| 2 | WSL guest设备 | `/dev/dxg`存在。 | WSL GPU虚拟化没有暴露给发行版。 |
| 3 | ICD inventory | `diagnose_wsl_vulkan.sh`列出预期Vulkan JSON。 | Mesa/发行版ICD包或loader安装。 |
| 4 | loader见到物理设备 | `vulkaninfo --summary`显示非CPU GPU。 | 驱动、ICD或适配器路由。 |
| 5 | wgpu见到相同设备 | `WGPU_BACKEND=vulkan noir_wgpu_probe`显示相同物理适配器。 | wgpu枚举环境、backend变量或驱动兼容问题。 |
| 6 | Noir窗口验证 | ABI、scrollbar、navigation与row activation真实X11回归通过。 | Noir host/API迁移或X11环境。 |

## 4. 物理GPU出现后再执行性能流程

仅在probe显示 `Vulkan` + `DiscreteGpu` 或 `IntegratedGpu` 后，执行以下命令：

```bash
export WGPU_BACKEND=vulkan
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cargo build --release --manifest-path wgpu-verify/Cargo.toml --bin noir_winit_host

./tools/verify_frozen_list_abi.sh
./tools/verify_row_activation.sh
./tools/verify_scrollbar_plan.sh
./tools/verify_list_navigation_plan.sh
./tools/verify_virtual_list_scroll.sh
```

然后按 [`REAL_GPU_BENCHMARKING.md`](REAL_GPU_BENCHMARKING.md) 重新建立adapter/driver专属profile。禁止将当前llvmpipe registry或timestamp数值外推到该适配器。

## 5. 需要提供给上游的最小故障证据

如果物理GPU仍未在probe中出现，请提交以下四项，而不是只报告“wgpu看不到GPU”：诊断脚本完整输出、`wsl --version`、Windows GPU驱动版本，以及发行版/Mesa版本。这样可以判断问题位于WSL设备传递、ICD、Vulkan loader还是wgpu枚举层。

## References

[1] [wgpu 30.0.0 crate metadata and Rust version requirements](https://crates.io/crates/wgpu/30.0.0)

[2] [Mesa D3D12 driver documentation](https://docs.mesa3d.org/drivers/d3d12.html)

[3] [WSLg Vulkan support troubleshooting issue](https://github.com/microsoft/wslg/issues/1254)
