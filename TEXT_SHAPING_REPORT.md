# Noir 编译期 Text Shaping 与多 Atlas Page 资源计划

**作者：Manus AI**  
**实验目标：** 将 dashboard 的静态标题文本从运行时字符串处理路径移入 `#lang noir/ui` 的宏展开期，并以固定 glyph range、固定 atlas page、固定实例槽和固定 GPU storage 地址交付给 wgpu/X11 宿主。动态数字文本保留受限的 `text-run` 路径，但其写入范围在编译期静态分配，且不覆盖静态标题资源。

> 本实验实现的是一个**受限、可证明的 ASCII shaping 前端**，不是通用 OpenType 文本系统。其价值在于把可静态确定的文本工作完全前移：运行时没有字符串扫描、没有 UTF-8 解码、没有 glyph lookup、没有 atlas packing、没有 layout 求解，也不会重新计算可写 GPU 区间。

## 1. 编译期—运行时资源契约

示例中的静态标签为 `NOIR CAUSAL GPU DASHBOARD`，由 `shape-static-ascii` 在宏展开期映射至 page 1 的 glyph ID 序列。字体字符表被刻意限制为 **空格 + `A`–`Z`**；不在该表内的静态字符会触发编译期错误，而不是把不可预测的字符处理带入宿主。

| 项目 | 编译期产物 | 运行时行为 | 不变量 |
|---|---|---|---|
| 静态标题 | 25 个 page-1 glyph ID、25 个 advance、`glyph_offset = 0` | 初始化时一次性写入 glyph storage | 所有交互 action 都不写入 `[0, 800)` |
| FPS/latency | 两个 page-0 数字 range，各 3 cell | action 仅覆写对应 96-byte range | `fps=[800,896)`；`latency=[896,992)` |
| Atlas | 两页 `R8Unorm` 的 `texture_2d_array` | 创建时各上传一次 | page 0 与 page 1 互不重叠 |
| 实例 ABI | 15 个固定 44-byte `QuadInstance` 槽 | 直接按预先分配的 offset 绑定/绘制 | 标题与动态 run 无需运行时布局 |
| 进度条 | `size.x` 的固定字段 offset | 点击后仅写 4 byte | `[316,320)`，独立于 glyph storage |

标题使 glyph 资源预算由原先两组动态数字的 **6 cells** 增至 **31 cells**。其中静态标题占 25 cells，两个动态数字 run 仍各占 3 cells；此变化是宏展开期 `resource_budget.glyph_capacity` 的计算结果。

## 2. Glyph ID 与 Atlas Page ABI

每个 glyph cell 仍为 **32 bytes**。本阶段使用其首个 `u32` 存储编码后的 glyph ID：

```text
glyph_id = (atlas_page << 16) | glyph_index
```

| 范围 | Atlas page | glyph index | 物理内容 | 使用者 |
|---|---:|---:|---|---|
| `0x0000_0000`–`0x0000_0009` | 0 | 0–9 | 3×5 数字点阵 | 动态 `fps` / `latency` action |
| `0x0001_0000`–`0x0001_001A` | 1 | 0–26 | 空格及 `A`–`Z` 的 3×5 点阵 | 编译期静态标签 |

两个 page 的物理尺寸统一为 `162 × 8` 像素，即 `27 cells × 6 px` 宽，每个 cell 是 `6 × 8` 像素。page 0 只使用前 10 个 cell；保持两页同宽使 WGSL 的 cell-to-UV 公式完全固定，避免了按页读取尺寸、重建坐标或分支处理不同纹理尺寸。

`host_text.wgsl` 在顶点阶段读取 glyph storage 的首个字：低 16 位决定 `glyph_index`，高 16 位传递为带 `@interpolate(flat)` 的离散 `atlas_page`。片段阶段以该 page 为 texture array layer 采样。因此页面选择是已经存入 GPU buffer 的数据，而非运行时字符串决定的逻辑。

## 3. Racket 前端 lowering

`noir/ui/main.rkt` 的关键 lowering 规则如下。

| DSL 文本形式 | Binding 分类 | `c-binding` 编译期字段 | Layout Plan 字段 |
|---|---|---|---|
| 静态字符串 `"NOIR ..."` | static shaped | `state = #f`、page 1、固定 ID 列表和 advance 列表 | `atlas_page`、`glyph_ids`、`glyph_advances`、固定 `glyph_offset` |
| `#:dynamic` 数字 text-run | dynamic numeric | state symbol、page 0、固定 max-char range | 固定 `glyph_offset` 与 `glyph_count`；action 内的 `gpu_update` |

静态 binding 不参与 `declared-state-ids` 检查，动态 binding 仍必须引用已声明状态。这一分界防止“静态字符串也被当作状态依赖”造成错误，并维持 `scene-dynamic-node-count = 3`：只有 `fps`、`latency` 与 `progress` 在运行时变化。

Layout Plan JSON 现在携带 `atlas_page`、`glyph_ids` 与 `glyph_advances`。对标题，compiler oracle 固化为：

```text
glyph_offset = 0
glyph_count  = 25
atlas_page   = 1
glyph_ids    = [65550, 65551, 65545, ..., 65540]
```

其中 `65550 = 0x0001_000E`，对应 page 1 的 `N`。数值序列而非原始字符串才是宿主真正消费的文本资源。

## 4. wgpu/X11 宿主最短路径

`wgpu-verify/src/bin/noir_winit_host.rs` 以 `serde` 解码 Scene JSON 后执行以下有限工作。

1. 宿主校验每个静态 run 的 `glyph_ids.len() == glyph_count`、advance 数量匹配，并验证每个 ID 的高 16 位等于 compiler 输出的 `atlas_page`。
2. 宿主创建一个 `D2Array`、两个 layer 的 `R8Unorm` atlas；page 0 上传数字点阵，page 1 上传固定 ASCII 点阵。
3. `initial_glyph_bytes` 仅在初始化时将静态 `glyph_ids` 写入其编译期分配的 glyph cell。随后才以已有的数字 formatter 填充动态 action range。
4. 渲染时，实例已经包含 NDC rect、glyph storage word offset 与 glyph count。静态文本只执行预定 draw；不进行字符串处理或字体系统调用。
5. 点击 action 仍只执行其既有 `gpu_update` 或 `instance_update`。对本例，刷新 FPS/latency 不会触碰标题 storage；进度按钮仅写 4-byte `size.x`。

这使静态标题从“可能随每帧或每次 layout 被解释的 UI 属性”转变成初始化期一次性 GPU 资源写入。页面选择、文本长度、draw 顶点数与 buffer 地址均来自编译产物。

## 5. 验证证据

下表记录本阶段已执行的真实验证，而非仅进行静态代码审阅。

| 验证层 | 执行内容 | 结果 | 证明的性质 |
|---|---|---|---|
| Racket 编译 | 以 `PLTCOLLECTS="$PWD:"` 导出 `out/shaped.scene.json` | 成功；`glyph_capacity=31` | 静态标题计入资源预算，Scene JSON 含新字段 |
| DSL 回归 | `PLTCOLLECTS="$PWD:" racket tests/run.rkt` | 成功 | 静态 title 的 page、25 个 glyph ID、advance 列表、动态偏移 800/896 通过 compiler oracle |
| Rust 编译 | `cargo build --release --bin noir_winit_host` | 成功 | Rust 1.75 / wgpu 0.20 下 D2Array、WGSL、host ABI 均可构建 |
| 真实 GPU + Surface | `WGPU_BACKEND=vulkan`，Xvfb 上启动 winit Surface | 成功；Vulkan/llvmpipe 路径 | D2Array atlas 和多页 WGSL pipeline 被真实创建与绘制 |
| 真实 X11 输入 | `xdotool` 依次点击三个 compiler Event Map rect | 成功 | Event hit-test 与 action dispatch 在真实窗口事件循环中闭环 |
| 局部 GPU 写入 oracle | 检查宿主日志 | 成功 | `fps [800,896)`、`latency [896,992)`、`progress [316,320)` 精确且互不重叠 |
| 静态资源 oracle | 检查宿主初始化日志 | 成功 | `compiler text resources: 1 static shaped run(s), 2 dynamic text-run action(s)` |

端到端验证的关键日志为：

```text
compiler text resources: 1 static shaped run(s), 2 dynamic text-run action(s)
glyph-patch fps: [800..896)
glyph-patch latency: [896..992)
instance-patch progress: [316..320)
winit host multi-page Glyph Atlas + static shaping + Event Map roundtrip verified.
```

## 6. 可复现实验

从 `noir-racket-ui` 目录执行：

```bash
PLTCOLLECTS="$PWD:" \
NOIR_COST_PROFILE="$PWD/profiles/registry.json" \
NOIR_PROFILE_ID="noir-vulkan-gpu-matrix-v1" \
racket tools/export-dashboard.rkt out/shaped.scene.json

cd wgpu-verify
cargo build --release --bin noir_winit_host
cd ..
./tools/verify_winit_host.sh out/shaped.scene.json

PLTCOLLECTS="$PWD:" racket tests/run.rkt
```

验证脚本会在 Xvfb 中启动实际 X11 窗口，使用 `xdotool` 点击三个 Event Map 给出的固定区域，并对日志中的静态 shaped run 与三个精确 GPU 写入区间进行断言。

## 7. 当前边界与下一步

该阶段有意采用等宽的 3×5 ASCII 点阵，因此 `glyph_advances` 是 compiler 交付的、可审计的度量计划；当前 shader 使用固定等距 placement，不需要为这组等宽 glyph 在运行时做前缀和。它不等同于复杂脚本的 OpenType shaping，也不处理 Unicode、组合字符、双向文本、kerning 或 fallback font。

下一阶段可在不破坏本 ABI 的前提下扩展为：将静态 run 的每 glyph 位置直接 lowering 为预分配 instance/vertex 子范围，或将非等宽的 prefix positions 在宏展开期写入专用 storage。这两个方向都应维持同一原则：**runtime 接收已布局的字形数据和固定 range，而不接收待解释的字符串。**

## 8. 相关实现文件

| 文件 | 责任 |
|---|---|
| `noir/ui/main.rkt` | 静态 ASCII shaping、binding 分类、glyph budget、Layout Plan JSON lowering |
| `examples/dashboard.rkt` | 含静态 title 与两个动态数字 text-run 的验证场景 |
| `wgpu-verify/src/bin/noir_winit_host.rs` | D2Array atlas 创建、JSON 资源契约校验、静态 glyph 初始写入、X11 host |
| `wgpu-verify/src/host_text.wgsl` | high/low 16-bit glyph ID 解码与 texture array layer 采样 |
| `tools/verify_winit_host.sh` | Xvfb/xdotool 端到端输入与局部写入 oracle |
| `tests/run.rkt` | 宏展开期 resource/layout/shaping 回归断言 |

> 结论：Noir 已将静态标题从高层 UI 字符串成功 lowering 为固定 page-1 glyph storage，且通过真实 wgpu/X11 路径验证。动态数字路径仍保有最小 96-byte 局部 patch，静态范围与动态范围在编译期可审计地分离。
