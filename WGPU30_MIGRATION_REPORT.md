# Noir wgpu 30 / Rust 1.87 迁移记录

**状态：已完成并在 X11 + Vulkan llvmpipe 环境回归。**主线已从 Rust 1.75 / wgpu 0.20 迁移到 Rust 1.87 / wgpu 30.0.0。旧基线保留为 Git tag `wgpu-0.20-rust-1.75-baseline`，指向迁移前的提交 `ce2d72b`。

> 本次升级提高了现代Vulkan、Mesa与WSL图形栈上的适配器枚举兼容性；它不保证WSL会因此自动获得物理GPU。物理GPU准入必须由同一版本的 `noir_wgpu_probe` 实测证明。[1]

## 1. 工具链与依赖

| 项目 | 迁移前 | 迁移后 | 约束 |
|---|---:|---:|---|
| Rust | 1.75 | 1.87.0 | 根目录 `rust-toolchain.toml` 固定。 |
| wgpu | 0.20 | 30.0.0 | `Cargo.toml` 精确锁定。 |
| winit | 0.29.15 | 0.29.15 | 继续仅启用 X11 / `rwh_06`。 |
| 历史回退点 | 无显式tag | `wgpu-0.20-rust-1.75-baseline` | 不删除旧证据。 |

wgpu 30的MSRV为Rust 1.87，因此维持Rust 1.75和升级wgpu 30不能同时成立。[1]

## 2. 已完成的API迁移

| 类别 | 0.20接口 | 30接口 | Noir处理方式 |
|---|---|---|---|
| texture upload | `ImageCopyTexture` / `ImageDataLayout` | `TexelCopyTextureInfo` / `TexelCopyBufferLayout` | 仅替换描述符名，保留atlas字节布局。 |
| surface acquire | `Result<SurfaceTexture, SurfaceError>` | `CurrentSurfaceTexture` 状态 | 显式区分 `Success`、`Suboptimal`、`Lost`、`Outdated`、`Timeout`、`Occluded` 与 `Validation`。 |
| present | `SurfaceTexture::present` | `Queue::present` | submit后由同一queue呈现。 |
| poll / map | `Maintain::Wait` 与直接mapped view | `PollType::wait_indefinitely()` 与`Result<BufferView>` | timestamp采样失败保持非致命`None`；differential readback传播上下文错误。 |
| pipelines | 直接layout/entry-point/buffer layout | 可选layout槽、可选entry point、新cache字段 | 无改动shader语义或Noir draw range。 |
| render pass | 隐式multiview/depth slice | 显式字段 | 全部设为`None`；不启用新的多视图路径。 |

迁移同时修复了一个独立的精度问题：运行时scissor从NDC派生的编译期整数几何此前因`as u32`截断可变为`33,143`；现在使用`round()`，恢复Scene proof的`34,144`局部范围。该修改收紧实现以匹配既有artifact，不改变ABI。

## 3. Scene 兼容性边界

旧静态`virtual-list` fixture将 `data_register_table` 编码为布尔值 `false`；data-register table方案将其编码为表对象。Rust宿主现在只兼容两种已定义表示：对象表示启用的表，`false`表示未启用。`true`仍在反序列化阶段拒绝，避免把松散兼容性变成未证明的Scene输入。

## 4. 验证矩阵

| 验证 | 结果 | 关键证据 |
|---|---|---|
| Racket全量回归 | 通过 | `PLTCOLLECTS="$PWD:" racket tests/run.rkt`。 |
| Rust 1.87 / wgpu 30 release | 通过 | `cargo build --release --bin noir_winit_host`。 |
| X11/Vulkan启动期proof | 通过 | ABI contracts、row activation、scrollbar、list navigation、timestamp query均完成。 |
| ABI freeze | 通过 | 接受精确contracts；拒绝revision、schema与必需字段漂移。 |
| row activation | 通过 | 行释放与Enter均走固定Action Slot→coalesced batch→no-packets请求。 |
| scrollbar | 通过 | 中段drag映射到viewport 4999，复用4-slot ring与局部tile。 |
| list navigation | 通过 | End、PageUp、PageDown、Home均走静态transition。 |
| static virtual-list scroll | 通过 | 10条编译期transition、8 instance / 32 glyph patch与局部subrange均通过。 |
| adapter probe | 通过 | 当前沙箱显示Vulkan `Cpu/llvmpipe`，正确拒绝将其称为真实GPU。 |

## 5. WSL真实GPU下一步

在WSL电脑执行：

```bash
./tools/diagnose_wsl_vulkan.sh | tee out/wsl-wgpu30-diagnostics.txt
```

只有当 `WGPU_BACKEND=vulkan ./wgpu-verify/target/release/noir_wgpu_probe` 显示 `type=DiscreteGpu` 或 `IntegratedGpu` 时，才继续执行 [`REAL_GPU_BENCHMARKING.md`](REAL_GPU_BENCHMARKING.md) 的校准与GPUI对照。详见 [`WSL_DOZEN_GPU_DIAGNOSTICS.md`](WSL_DOZEN_GPU_DIAGNOSTICS.md)。

## References

[1] [wgpu 30.0.0 crate metadata and Rust version requirements](https://crates.io/crates/wgpu/30.0.0)
