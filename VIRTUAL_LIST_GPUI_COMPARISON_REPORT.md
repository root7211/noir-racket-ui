# Noir Virtual List 与 GPUI 对照实验报告

**作者：Manus AI**  
**范围：** 固定容量虚拟列表 DSL、编译期 viewport 规划、真实 X11/Vulkan 验证，以及与 GPUI `uniform_list` 的受限同场景输入处理对照。

## 结论摘要

Noir 已新增受限的 `virtual-list` 与 `row-template` DSL。容量、可见行数、行高、文本容量、行 ID、row instance offset 和首 viewport 的 row-tile 地址均由 Racket 宏系统在编译期固定。运行时宿主只接受 Scene 中的已证明计划，不测量行高、不遍历 UI 树、不动态构造行资源。

首个 fixture 是容量为 8、可见 3 行、行高 28 px 的 `telemetry-list`。编译器输出的 viewport 高度为 84 px，首 viewport 的独立 row-tile 地址为 `[0, 1, 2]`。Rust 宿主在启动期重新验证容量、行 ID 唯一性、row instance offset 与 Layout Plan 对应关系、viewport 等式及 row-tile 前缀约束；真实 X11/Vulkan oracle 已通过。

为了建立可运行的 GPUI 对照，实验使用官方 GPUI 0.2.2 的 `uniform_list`，配置为同样的 8 条固定文本、28 px 行高和 84 px 三行 viewport。由于 GPUI 0.2.2 使用 Rust 2024 edition 且官方要求最新 stable Rust，因此对照工程使用隔离 Rust 1.97.1；Noir 本体继续以系统 Rust 1.75 构建，未改变兼容性约束。[1]

> 本报告中的 Noir/GPUI 数字是 **X11 输入 burst 到全部应用 handler 日志完成** 的端到端指标，不是 GPU frame time、present latency 或完整渲染吞吐。不能据此宣称任一框架拥有总体渲染性能优势。

## DSL 与编译期布局产物

```racket
(virtual-list #:id telemetry-list
              #:capacity 8
              #:visible-rows 3
              #:row-height 28
              #:max-chars 8
  (row-template ((node-aa "NODE AAA") ... (node-hh "NODE HHH"))))
```

| 编译器产物 | 固定值 | 含义 |
|---|---:|---|
| `capacity` | 8 | 静态展开的 row-template 数量与资源上限 |
| `visible_rows` | 3 | 初始 viewport 的行数 |
| `row_height` | 28 px | 编译期固定行高 |
| `viewport_height` | 84 px | `visible_rows × row_height` |
| `row_layout_offsets` | 176…792 bytes | 每行对应的固定 `QuadInstance` 地址 |
| `visible_row_tile_ids` | `[0, 1, 2]` | 独立 virtual row-tile arena 的首 viewport 前缀 |

`visible_row_tile_ids` 不复用既有 action-damage render tile 的索引。后者只描述由 Action 影响的 draw tile；virtual list 因而拥有独立、dense、compiler-fixed 的 row-tile arena，行 `i` 永远对应 tile `i`。未来 scroll lowering 只需选择同一固定 arena 的另一段连续前缀，而不需在运行时搜索 render tree。

## 宿主反向证明与真实验证

Rust `compiler_virtual_list_plans` 在窗口创建前执行以下检查：每个计划容量非零；可见行数处于 `[1, capacity]`；viewport 高度严格等于行数乘行高；行 ID、row offset 数量与容量一致；row ID 不重复；每个 offset 与 Layout Plan 中同 ID 节点的 instance offset 一致；offset 单调递增；初始可见 row tile 恰为 `[0, …, visible_rows-1]`。

`tools/verify_virtual_list_plan.sh` 会重新导出 Scene、检查完整 JSON artifact、启动 Xvfb/Vulkan release host，并要求日志出现已验证的 `telemetry-list capacity=8 viewport=3x28 row-tiles=[0, 1, 2]`。该 oracle 已通过。同时，Noir 的全量 Racket 回归与 Rust release build 通过。

## GPUI 对照设计

GPUI 对照程序只包含三项与 Noir fixture 对齐的可见工作：标题、三位 refresh counter 和 8-capacity/3-visible-row/28-px-row `uniform_list`，另有一个更新 counter 并调用 `cx.notify()` 的 `REFRESH` 控件。GPUI 的 `uniform_list` 是其官方示例提供的列表虚拟化 API。[2]

两侧均在同一 Ubuntu/Xvfb 1280×720 环境，通过 Vulkan llvmpipe 软件适配器运行，并由窗口相对坐标发出 25 次零间隔左键输入。每个样本只在 25 个框架端 handler 日志均出现后停止计时；总计 15 个独立样本。Noir handler 完成意味着 `refresh-count` State Slot 写入与已编译 RenderRequest 入队；GPUI handler 完成意味着 counter 递增及 `cx.notify()` 调用。

| 框架 | 中位数 ms / handler | P95 ms / handler | 最小–最大 ms / handler | 完成事件 |
|---|---:|---:|---:|---:|
| Noir | 0.999 | 1.109 | 0.458–1.144 | 375 / 375 |
| GPUI | 0.975 | 1.549 | 0.946–1.570 | 375 / 375 |

Noir 相对 GPUI 的中位数为 **+2.45%**，落在该实验的 X11 注入、进程调度和日志轮询噪声范围内；两者在此受限输入指标上应判定为**没有可证明的中位数胜负**。Noir 的 P95 较低，但样本量和软件适配器环境不足以推广为框架级尾延迟结论。

![Noir 与 GPUI virtual-list X11 输入处理对照](wgpu-verify/out/noir-gpui-virtual-list-input-comparison.png)

## 性能解释与边界

Noir 的独特价值没有被这项微型对照完整测试。当前 fixture 的行内容是静态的；refresh action 仅更新一个固定三字节 text-run，并不会触发真正 scroll、行 recycle 或 viewport transition。因此，该对照只证明三件事：Noir 的 virtual-list compiler artifact 能被真实宿主接受；GPUI 的真实 `uniform_list` 能在同一 X11 环境处理等价的 refresh state change；两个原型均可稳定处理零间隔输入 burst。

GPUI 官方说明其 View 每帧构造 element tree，并通过 retained `Entity`、低级 Element 与列表 API 覆盖广泛应用需求。[1] Noir 的目标则是对受限 DSL 的可证明部分在编译期固定资源和依赖。要比较这一战略差异，下一轮必须实现真正的 scroll transition：Noir 选择预编译 row-tile range 并仅 patch 离开/进入 viewport 的行；GPUI 使用 `uniform_list` 的原生 scroll 路径。然后需要采集同一硬件 GPU 上的 input-to-present、CPU frame time、GPU timestamp、draw/dispatch/submit count、峰值内存以及 p95/p99。

## 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

# Noir DSL artifact 与真实 Vulkan oracle
PLTCOLLECTS="$PWD:" racket tests/run.rkt
tools/verify_virtual_list_plan.sh

# GPUI comparator: requires isolated modern toolchain installed under ~/.cargo-gpui
RUSTUP_HOME=/home/ubuntu/.rustup-gpui \
CARGO_HOME=/home/ubuntu/.cargo-gpui \
  /home/ubuntu/.cargo-gpui/bin/cargo build --release \
  --manifest-path gpui-virtual-list-benchmark/Cargo.toml

# 15-round X11 input-to-handler comparison and summary
./tools/sample_noir_gpui_virtual_list_input.sh 15 25
./tools/summarize_noir_gpui_virtual_list_input.py \
  wgpu-verify/out/noir-gpui-virtual-list-input-samples.jsonl \
  wgpu-verify/out/noir-gpui-virtual-list-input-summary.json
./tools/plot_noir_gpui_virtual_list_input.py \
  wgpu-verify/out/noir-gpui-virtual-list-input-summary.json \
  wgpu-verify/out/noir-gpui-virtual-list-input-comparison.png
```

## References

[1]: https://crates.io/crates/gpui "GPUI 0.2.2 official crate page"
[2]: https://github.com/zed-industries/zed/blob/main/crates/gpui/examples/uniform_list.rs "GPUI official uniform_list example"
