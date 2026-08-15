# Noir 固定 Row-Tile Scroll Transition 与 GPUI 对照报告

**作者：Manus AI**  
**范围：** Noir `virtual-list` 的真实滚动路径、编译期 viewport transition proof、真实 X11/Vulkan 验证，以及与 GPUI `uniform_list` 原生滚动的受限同场景对照。

## 结论

Noir 的 `virtual-list` 不再只是初始 viewport 的静态布局说明。它现在拥有一个**有限、完全编译期生成的 viewport 状态机**。对于容量 8、可见 3 行、行高 28 px 的 `telemetry-list`，编译器生成 6 个离散 viewport slot（行 0–2 至行 5–7）与 10 条有向相邻 transition。运行时滚轮事件不测量行高、不遍历行节点、不搜索 glyph、不合并 damage；它只以当前 slot 和滚动方向索引其中一条已证明边。

一次相邻滚动会从 compiler artifact 直接取得目标连续 row-tile 范围、8 个 `QuadInstance.pos.y` 写入和 32 个 `GlyphPlacementInstance.pos.y` 写入。对于 3 行 viewport，源/目标行集合的并集恒为 4 行；每行有 2 个 quad 和 8 个 glyph placement，因此该数量是编译期可证明的，不依赖运行时数据结构。

> **真正的运行时路径：** `X11 MouseWheel → current viewport slot + direction → compiler transition → 8 instance writes + 32 glyph writes → RenderRequest(no-packets, scroll slot) → 572×84 scissor submit`。

## 编译期 Scroll Plan

| 产物 | telemetry-list 值 | 编译期含义 |
|---|---:|---|
| capacity | 8 | 静态row-template资源上限 |
| visible rows | 3 | 任一viewport的固定可见容量 |
| row height | 28 px | 无运行时测量的行步长 |
| viewport height | 84 px | `3 × 28` |
| viewport slots | 6 | `0…5`，分别对应连续三行窗口 |
| directed transitions | 10 | 相邻slot双向边，`2 × (8 - 3)` |
| row tile range | 3个连续ID | 例如 `0→1` 为 `[1,2,3]` |
| instance Y patches | 8 | 4个受影响行 × 每行2个quad |
| glyph Y patches | 32 | 4个受影响行 × 每行8个glyph |
| packet activity worklist | `no-packets` / slot 2 | scroll不写glyph ID或dynamic packet payload |

编译器为每条边输出 `from_slot`、`to_slot`、`visible_row_tile_ids`、`instance_y_patches`、`glyph_y_patches` 和固定 `scissor`。不可见行的目标Y位置固定为 -3.0 NDC；可见行的位置使用同一Layout Plan坐标公式预先计算。因为每个row-template及其文本placement在初始Scene中已分配固定地址，scroll不发生buffer重分配、glyph重shaping或atlas查询。

## 宿主 Admission Proof 与执行

Rust host 在窗口创建前重建并检查以下不变量：每条边仅跨越一个相邻slot；边数恰为10且不重复；目标row tile必须是精确连续范围；instance patch offset必须与源/目标四行的 compiler-emitted row instance address table严格相等；glyph patch offset同样必须与四行的固定placement slot集合严格相等；scissor必须等于Layout Plan的NDC反算结果。

一份将 `0→1` transition 的第一个row tile从1篡改为0的Scene，在窗口创建前被拒绝：

> `virtual list telemetry-list scroll edge 0 -> 1 has widened or incorrect row-tile range`

真实X11/Vulkan滚轮回归已确认 `0→1` 选择`[1,2,3]`，再到`1→2`选择`[2,3,4]`，每边严格使用8项instance与32项glyph补丁，并提交固定的`572×84+34,144` viewport scissor。GPU packet activity记录为 `no-packets` 空worklist skip，因此scroll不会扩大glyph packet写入范围。

## GPUI 对照与性能测量

GPUI对照程序使用官方 `uniform_list` API，保持容量8、行高28 px、3行viewport和640×360窗口。它通过真实X11 wheel-down输入达到同一末端可见范围`5..8`；其processor日志确认了原生可见范围从初始前缀转移到`5..8`。GPUI参考实现使用隔离的最新stable Rust工具链，Noir主线仍使用Rust 1.75。[1] [2]

每轮实验从初始三行viewport出发，发送3次零间隔X11 wheel-down输入；计时从第一项输入发出开始，到框架确认末端三行`5..7`可见为止。共采集15轮。该数字包含X11注入、进程调度、日志和轮询；**它不是GPU timestamp、frame time、input-to-present或完整渲染吞吐。**

| 框架 | 中位数 ms | P95 ms | 最小–最大 ms | 完成条件 |
|---|---:|---:|---:|---|
| Noir | 6.283 | 7.086 | 5.989–7.713 | compiler viewport slot 5 / row tiles `[5,6,7]` |
| GPUI | 6.526 | 11.673 | 5.987–21.284 | `uniform_list` visible range `5..8` |

Noir的该受限endpoint指标中位数相对GPUI为 **-3.73%**。由于中位数差异仅约0.24 ms且包含外部X11/日志开销，不能据此宣称总体性能领先；不过GPUI在本15轮、软件Vulkan环境中呈现更高的P95和一次21.284 ms离群样本。该尾部现象需要在真实硬件GPU、更多样本和可比较presentation测量下再判断。

![Noir 与 GPUI scroll endpoint 对照](wgpu-verify/out/noir-gpui-virtual-list-scroll-comparison.png)

## 关键边界与下一步

当前Noir scroll使用最小**写入范围**和最小**fragment scissor范围**，但render pass仍通过一个固定viewport scissor绘制全实例/全glyph packet列表。因此它已经消除了运行时依赖推导、资源寻址和完全canvas重绘，却尚未实现每行draw-range级的顶点提交裁剪。下一步应使独立row-tile arena同时带有已证明的 `DrawRange` 与glyph packet subrange，以把scroll提交从“所有静态顶点 + viewport scissor”进一步降低为“仅四个受影响row tile的draw/glyph subrange”。

这也会形成更严格的GPUI比较：容量应扩展到1,000和10,000行，并在硬件GPU上采集CPU frame time、GPU timestamp、draw/dispatch/submit数量、input-to-present与p95/p99。当前结果证明的是Noir的**编译期有限scroll状态机**在真实X11/wgpu路径中工作并保持proof边界，而非它已经在通用滚动性能上击败GPUI。

## 复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

# Noir compiler artifact、真实滚轮、tampered proof rejection
PLTCOLLECTS="$PWD:" racket tests/run.rkt
tools/verify_virtual_list_scroll.sh

# GPUI comparator (isolated modern Rust; Noir remains on Rust 1.75)
RUSTUP_HOME=/home/ubuntu/.rustup-gpui \
CARGO_HOME=/home/ubuntu/.cargo-gpui \
  /home/ubuntu/.cargo-gpui/bin/cargo build --release \
  --manifest-path gpui-virtual-list-benchmark/Cargo.toml

# 15-round endpoint comparison
./tools/sample_noir_gpui_virtual_list_scroll.sh 15
./tools/summarize_noir_gpui_virtual_list_scroll.py \
  wgpu-verify/out/noir-gpui-virtual-list-scroll-samples.jsonl \
  wgpu-verify/out/noir-gpui-virtual-list-scroll-summary.json
./tools/plot_noir_gpui_virtual_list_scroll.py \
  wgpu-verify/out/noir-gpui-virtual-list-scroll-summary.json \
  wgpu-verify/out/noir-gpui-virtual-list-scroll-comparison.png
```

## References

[1]: https://github.com/zed-industries/zed/blob/main/crates/gpui/examples/uniform_list.rs "GPUI official uniform_list example"
[2]: https://crates.io/crates/gpui "GPUI official crate page"
