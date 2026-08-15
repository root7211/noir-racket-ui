# Row-Tile Draw-Range 与 Glyph Subrange Lowering 报告

**作者：Manus AI**  
**目标：** 让 Noir `virtual-list` 的滚动路径不再提交列表外的quad/glyph顶点；每次scroll仅消费compiler-proved目标viewport row-tile范围。

## 结果摘要

Noir此前已经将滚动的GPU**写入**收敛为4个受影响行：8个quad Y坐标和32个glyph Y坐标的固定patch，并使用84 px viewport scissor限制片段区域。但scroll render pass仍绘制全部静态实例和全部glyph packet，依靠scissor丢弃列表外片段。

本次实现把每个row-template的资源地址进一步lower为两个不可变compiler artifact：`row_draw_ranges` 和 `row_glyph_subranges`。Renderer对目标viewport的3个row-tile只提交3个quad range、6个quad实例、3个glyph range和24个glyph placement；不再调用全实例范围或`draw_all_glyph_packets`。

> **优化后scroll路径：** `MouseWheel → fixed viewport transition → 8 instance Y writes + 32 glyph Y writes → [3 row DrawRange, 3 glyph subrange] → 572×84 scissor submit`。

## 编译期 Lowering

`virtual-list` planner从固定row subtree的Layout Plan与Glyph Placement Plan读取每行资源地址。它要求：每行quad instance slot严格连续；每行glyph placement slot严格连续。若模板资源不是单一连续区间，宏展开期拒绝该列表，而不是把分段搜索或合并留给运行时。

| Row-Tile artifact | `telemetry-list`（8行） | 意义 |
|---|---:|---|
| quad DrawRange | `[4,2]`, `[6,2]`, …, `[18,2]` | 每行2个连续quad实例 |
| glyph subrange | `[20,8]`, `[28,8]`, …, `[76,8]` | 每行8个连续glyph placement |
| 目标viewport | 3个连续row-tile | 例如slot 1为`[1,2,3]` |
| scroll patch rows | 4 | 离开行、两个保留行、进入行 |
| scissor | `34,144,572,84` | 固定viewport fragment范围 |

Scene ABI中的每行range由`{ first, count }`编码。它们不是draw调用的运行时推导结果，而是Racket在静态row-template展开、固定布局slot分配和glyph placement lower完成后输出的结果。

## 启动期反向 Proof

Rust host在创建窗口前验证：range表长度必须等于列表capacity；每行原始instance offset与glyph slot均连续；每个row DrawRange必须恰好覆盖该行compiler address table；每个glyph subrange必须恰好覆盖该行placement table；行范围不能重叠。scroll transition proof继续验证相邻slot、连续row tile范围、精确4行Y patch集合和canonical scissor。

篡改Scene中第一行的quad range count（`2 → 3`）会在创建窗口前被拒绝：

> `virtual list telemetry-list row 0 draw range does not exactly cover compiler instances`

这意味着运行时不能通过伪造更大的顶点范围逃逸编译器的row-tile覆盖边界。

## 真实 X11/Vulkan 验证

真实X11 wheel-down输入触发`0 → 1`后，日志记录：

```text
virtual-list scroll: list=telemetry-list from=0 to=1 row-tiles=[1, 2, 3]
instance-patches=8 glyph-patches=32
virtual-list scroll-submit: list=telemetry-list viewport=1
quad-ranges=3 quad-instances=6 glyph-subranges=3 glyph-placements=24
worklist=no-packets
```

因此，列表本体的row顶点提交由此前的8行 × 2个quad实例与8行 × 8个glyph placement，缩小为可见3行的6与24：均为**62.5%**的列表顶点实例削减。初始基准Scene中还存在列表外的标题、状态文本和refresh控件；旧scroll pass会额外提交这些非列表实例，优化后它们也不进入scroll pass。这是严格的结构性削减，与软件GPU计时噪声无关。

| 项目 | 旧scroll提交 | 优化后提交 | 变化 |
|---|---:|---:|---:|
| 列表quad实例 | 16 | 6 | -62.5% |
| 列表glyph placement | 64 | 24 | -62.5% |
| row draw calls | 隐含于全实例调用 | 3个固定range | 仅目标viewport |
| row glyph calls | 全glyph packet路径 | 3个固定subrange | 仅目标viewport |
| GPU写入 | 8 quad Y + 32 glyph Y | 相同 | 不扩大写入范围 |
| packet activity | `no-packets` | `no-packets` | 不触碰packet payload |

## GPUI 同场景对照

重新在同一Xvfb/Vulkan llvmpipe环境下采集15轮：从初始三行viewport发送3次零间隔wheel-down，并在框架确认末端行5–7可见时停止计时。Noir使用优化后的row-tile subrange renderer；GPUI使用官方`uniform_list`路径。[1]

| 框架 | 中位数 ms | P95 ms | 样本数 |
|---|---:|---:|---:|
| Noir | 6.604 | 7.784 | 15 |
| GPUI | 6.597 | 36.558 | 15 |

Noir与GPUI中位数差异为 **+0.11%**，可视为该外部X11 endpoint指标下的噪声。GPUI P95受到一次约36.9 ms离群样本影响；不能据此推导一般性尾延迟优势。该测量包含X11事件注入、进程调度、日志与轮询，**不是GPU timestamp、frame time或input-to-present latency**。本优化的可确认收益是compiler artifact规定的顶点提交范围已收缩，而非该小型软件Vulkan场景的端到端时间胜负。

![Noir 与 GPUI row-tile scroll endpoint 对照](wgpu-verify/out/noir-gpui-virtual-list-scroll-comparison.png)

## 验证与复现

```bash
cd /home/ubuntu/noir_review/noir-racket-ui

PLTCOLLECTS="$PWD:" racket tests/run.rkt
tools/verify_virtual_list_scroll.sh

# 与GPUI同场景的15轮scroll endpoint测量
./tools/sample_noir_gpui_virtual_list_scroll.sh 15
./tools/summarize_noir_gpui_virtual_list_scroll.py \
  wgpu-verify/out/noir-gpui-virtual-list-scroll-samples.jsonl \
  wgpu-verify/out/noir-gpui-virtual-list-scroll-summary.json
```

## 下一步

应扩展fixture到1,000与10,000个静态容量行，并让row-tile arena输出固定glyph packet page subranges和indirect command ranges。这样才能量化在真实硬件GPU上，Noir避免提交数千个不可见row顶点时的CPU/GPU收益。随后添加selection/hover与固定capacity row recycling，验证该最短路径在真实GUI交互中保持成立。

## References

[1]: https://github.com/zed-industries/zed/blob/main/crates/gpui/examples/uniform_list.rs "GPUI official uniform_list example"
