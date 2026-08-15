# llvmpipe Vulkan 性能数据：解释边界、真实 GPU 差异与修正协议

**作者：** Manus AI  
**审计对象：** Noir Racket/wgpu 原型、`llvmpipe (LLVM 20.1.2, 256 bits)`、Vulkan、Xvfb/X11、640×360 基准与 GPUI 对照样本。  
**结论等级：** 本文将现有结果分为**可迁移的结构性证据**、**仅适用于当前llvmpipe环境的性能证据**和**尚未测量的真实GPU/呈现延迟证据**。

## 结论摘要

当前 llvmpipe 结果已经可靠证明 Noir 的编译期优化确实改变了执行图：例如 fusion 在相同 Scene、winner writes、tile union 与 glyph ranges 下把 `RenderRequest / packet dispatch / queue submit` 从 `3 / 3 / 3` 降为 `1 / 1 / 1`，这是与设备无关的 **66.7% 结构削减**。固定 row ring、局部 glyph/quad subrange、no-packets worklist 与 thumb 单地址 patch 同样是可审计的结构性事实。[4] [5]

但 llvmpipe 是以 LLVM 运行时代码生成和CPU多线程执行的软件光栅器；它并不呈现物理GPU的独立SM/CU、片上缓存、显存带宽、硬件调度、波前/warp占用、GPU时钟、PCIe传输和真实scan-out行为。[1] 因此**不能**把 llvmpipe 的纳秒值乘一个“换算系数”后称作真实GPU性能；修正方法是为每块真实GPU重新采样、重新生成profile/manifest，并只比较同一设备上由相同测量边界产生的数据。

> llvmpipe 的正确角色是：验证路径存在、工作范围没有扩大、优化方向有意义、测试协议可复现。它不是发布“Noir比GPUI快X%”或“该GPU时间为Y ns”的硬件性能证据。

| 当前结论 | 可信度 | 能否外推到真实GPU | 原因 |
|---|---|---|---|
| Fusion `3→1` request/dispatch/submit | 高 | **可以，作为结构计数** | compiler artifact 和宿主审计的离散工作量，不依赖吞吐率。 |
| 列表滚动只写固定ring / 局部glyph范围 / no-packets | 高 | **可以，作为工作范围证明** | 写地址、draw subrange、worklist均由Scene/Host proof固定。 |
| llvmpipe上 fusion GPU timestamp `-33.8%/-37.0%` | 中 | **不可以作为数值外推** | 仅说明该软件适配器上的相对路径收益。 |
| llvmpipe上 fusion CPU event-to-submit `-85.6%/-86.5%` | 中 | **只可外推“少走host路径”的方向** | 绝对值受CPU、Mesa、线程/调度和驱动批处理影响。 |
| Noir/GPUI scroll endpoint中位数 | 低 | **不可以** | 指标排除GPU present，包含X11注入、调度、日志与轮询。 |
| Input-to-photon / display latency | 无 | **尚未测量** | Xvfb无物理显示链路，当前没有presentation或外部光学时间戳。 |

## 1. 当前证据台账

### 1.1 Vulkan/llvmpipe microbenchmark

当前单次 `wgpu-benchmark.json` 明确记录 adapter 为 `llvmpipe (LLVM 20.1.2, 256 bits)`、Vulkan backend、timestamp query enabled 与 `timestamp_period_ns=1.0`。三个case都满足 `expectations_match=true`：tile mask、winner bytes、glyph draw/instance count 与编译器artifact一致。[6]

| 单次case | Winner writes | Tiles | Glyph draw / instance | CPU event→submit | GPU timestamp region |
|---|---:|---:|---:|---:|---:|
| Progress activate | 28 B | 2 | 0 / 0 | 14.552 ms | 0.474 ms |
| FPS activate | 36 B | 2 | 1 / 3 | 0.171 ms | 0.487 ms |
| Latency activate | 36 B | 2 | 1 / 3 | 0.097 ms | 0.334 ms |

这里最重要的不是第一行的 `14.552 ms`，而是它与同一profile的多样本coalesced CPU中位数 `81.212 µs` 相差 **179.19×**。这直接证明单次冷启动CPU值不可用于相对比较，更不应被当作硬件性能结论。当前项目的后续matrix已经采用warm-up与分位数，这一方向是正确的。[6] [7]

### 1.2 llvmpipe profile 与 strategy 数值

现有 registry 与 `640×360` llvmpipe identity 精确绑定；六个校准proxy在CPU encode/submit与软件“GPU timestamp”之间的比值为 `1.37×–4.73×`，说明即使在同一个软件适配器内，不同workload也没有一个固定CPU/GPU转换关系。[7]

在该**同一软件环境**的replay matrix里，coalesced相对于full redraw的GPU中位数削减为：progress **44.43%**、FPS **59.92%**、latency **51.57%**。这些数值支持“减少范围通常有利”的工程假设；但不能推导“真实NVIDIA/AMD/Intel GPU也会是44–60%”。硬件GPU可能因pass合并、driver command buffering、cache、tile-based rasterization、异步queue或固定提交开销而放大、缩小乃至重排候选策略。

### 1.3 Fusion 数据

融合实验的控制变量最干净：baseline与fusion共用Scene、winner writes、tile union、glyph draw range、adapter和release binary，唯一变化是请求分区。15个独立进程样本的中位数为：

| Case | CPU event→submit | llvmpipe timestamp region | 结构变化 |
|---|---:|---:|---|
| Fuse Commit | 741.5→106.6 µs，`-85.6%` | 817.9→541.7 µs，`-33.8%` | 3 requests/dispatches/submits → 1 |
| Fuse Reset | 740.1→100.2 µs，`-86.5%` | 896.6→564.5 µs，`-37.0%` | 3 requests/dispatches/submits → 1 |

正确表述是：**在llvmpipe上，融合路径以同等覆盖范围减少了两条完整host/renderer路径，并观测到上述相对时间变化。** 不正确表述是：**Noir在真实GPU上会获得33–37%的GPU加速。**[5]

### 1.4 Noir / GPUI 数据

两份GPUI对照都已正确标注为非present指标。输入样本是`X11 input → handler log`；滚动样本是三次零间隔wheel输入至framework日志确认endpoint viewport。它们不包含可比的GPU timestamp、GPU completion或input-to-present。[8] [9]

当前原始滚动summary与旧报告存在版本漂移：summary的Noir/GPUI中位数是 **6.604 / 6.597 ms**，Noir相对GPUI为 **+0.113%**；旧报告中记录的是 **6.283 / 6.526 ms** 与 `-3.73%`。两组数都属于15样本的X11端点指标，不可混用。当前样本中两次GPUI约36 ms端点造成P95 `36.558 ms`；Noir最大值为 `7.864 ms`。配对15轮的中位 `Noir−GPUI` 是 **+0.186 ms**，符号方向为8正、7负，不能支撑胜负结论。[8]

| 当前原始对照 | Noir | GPUI | 合理解释 |
|---|---:|---:|---|
| 25次click的每handler中位数 | 0.999 ms | 0.975 ms | Noir `+2.45%`，在外部注入/日志噪声边界内。 |
| 3次wheel至endpoint中位数 | 6.604 ms | 6.597 ms | Noir `+0.113%`，实质平手。 |
| wheel endpoint P95 | 7.784 ms | 36.558 ms | 可记录为当前环境尾部现象，不能归因于renderer。 |

## 2. 为什么软件Vulkan与真实GPU不同

Mesa将LLVMpipe描述为使用LLVM runtime code generation的软件光栅器，并说明它以多线程利用CPU核心；shader、rasterization和vertex processing均被转换为主机机器码。[1] 这决定了当前“GPU”工作实际与host进程共享CPU、缓存层级、OS调度和可能的线程资源。物理GPU则具有独立执行资源和驱动/硬件队列；二者的竞争关系与吞吐瓶颈不是同一个问题。

| 偏差来源 | llvmpipe/Xvfb含义 | 真实GPU上的变化 | 对Noir结论的影响 |
|---|---|---|---|
| 执行资源 | raster、shader与driver工作落在CPU/JIT路径 | GPU shader/vertex/raster在专用硬件上运行 | CPU与“GPU timestamp”不再代表独立域；软件相对比不等于真实GPU比。 |
| 内存系统 | 主机缓存、DRAM与CPU vector width主导 | L2/VRAM/UMA、纹理缓存、PCIe/共享内存主导 | glyph/instance upload、tile大小和clip策略的拐点会改变。 |
| 并发与提交 | OS进程、Xvfb、软件driver线程会影响endpoint | 驱动批处理、queue深度、GPU异步执行和fence行为主导 | 3→1 submit的CPU收益仍有方向性，但幅度不可转移。 |
| shader/JIT | runtime LLVM codegen与CPU SIMD影响首帧、热身和cache | driver shader compiler、pipeline cache、wave occupancy影响首帧/热态 | 必须分别报告cold和steady-state，不能把单次值合并。 |
| 计时语义 | query region测量软件适配器实现的命令区间 | query region测量同一GPU queue上的近似命令执行时间 | 两者都不是present；timestamp period=1 ns是tick换算，不是精度/准确度保证。 |
| 呈现 | Xvfb没有实体scan-out、显示器刷新或compositor真实路径 | present mode、compositor、刷新率和display timing均会介入 | 不能从当前数据推断视觉延迟、掉帧或input-to-photon。 |

Vulkan timestamp query只记录命令执行处的tick；必须乘以device timestamp period换算为纳秒。Khronos同时指出，由于pipeline阶段可重叠，任意阶段组合不一定有意义，且不能比较不同queue的timestamp；其示例还指出同步读取结果可能造成不必要stall，生产测量应采用延迟可用性检查。[2] wgpu文档同样说明绝对timestamp没有意义，只能对同一串操作做差，并且pass可能并行或改变执行顺序。[3]

## 3. 修正原则：不是“乘系数”，而是重新校准

没有合法的方程可把 `T_llvmpipe` 转换成 `T_real_gpu`。原因是两者的关键成本项不是同比缩放：例如实GPU可能使fragment吞吐快数个数量级，却让小提交固定开销、pipeline切换、upload同步或present成为主导；而llvmpipe中的CPU/JIT竞争在实GPU中可能完全消失。

因此修正应采用以下规则。

| 结论类型 | 修正方法 | 发布标签 |
|---|---|---|
| 结构性工作量 | 继续使用compiler proof、write bytes、tile mask、draw/dispatch/submit count | `device-independent structural evidence` |
| CPU event→submit | 每台真实GPU机器重新采样；锁定CPU governor、核亲和/背景负载并报告host CPU | `host-path result on named system` |
| GPU command region | 每个adapter/driver/分辨率分别timestamp；只比较同queue、同boundary | `GPU command-region result` |
| End-to-end input | 记录input→handler、input→submit、submit→GPU completion为三个独立指标 | `application pipeline result` |
| 视觉延迟 | 使用presentation feedback或外部光学/高帧率测量 | `input-to-photon result`；没有该测量就不得声称 |

现有 profile matcher 已按backend、adapter和resolution精确绑定，这是正确防线；但 `profile_id` 名为 `noir-vulkan-gpu-matrix-v1` 容易被误读为通用GPU profile。应将当前artifact重命名或标注为 `noir-vulkan-llvmpipe-matrix-v1`，并永远不让真实GPU匹配它。[7]

## 4. 推荐的真实GPU校准协议

### 4.1 设备矩阵

至少选择一个AMD、一个NVIDIA和一个Intel真实Vulkan adapter；若资源有限，先选择部署目标GPU并把结论限定为该adapter。每台机器单独保存profile与manifest，不能跨GPU平均。

| 必须记录的identity | 示例 |
|---|---|
| GPU | vendor/device ID、GPU name、VRAM/UMA类型 |
| Driver | driver版本、Mesa/NVIDIA/Intel stack、Vulkan API版本 |
| Host | CPU型号、核心数、governor、内存、OS kernel、后台负载状态 |
| Display | 物理X11/Wayland选择、compositor、分辨率、缩放、刷新率、present mode |
| Build | git revision、Rust/wgpu/winit版本、release flags、Scene fingerprint、字体/atlas fingerprint |
| Timing | query features、timestamp period、query边界、warm-up/sample count、clock/power policy |

### 4.2 两段式采样

第一段是**device calibration matrix**：保留现有六类proxy，但每台设备做至少 warm-up 20、samples 200；输出原始JSONL、median、P95、P99、min/max、IQR和device manifest。第二段是**application workload matrix**：必须包含当前真实的列表交互路径，而不是只保留button batch。

| Workload | 固定语义checksum | 必须测量 |
|---|---|---|
| Fusion commit/reset | 相同winner writes、tile union、glyph range | CPU submit、GPU region、requests/dispatches/submits |
| 10k row wheel | 相同逻辑viewport和ring slots | row/glyph patches、draw ranges、GPU region |
| Scrollbar middle/end drag | 相同viewport、thumb address和tile mask | pointer→submit、thumb patch、GPU region |
| PageUp/PageDown/Home/End | 相同target viewport | keyboard→submit、ring、thumb sync、GPU region |
| Visible / offscreen data update | 相同data records和最终cell values | GPU bytes、glyph ranges、CPU/GPU region |
| 日志浏览器完整序列 | 相同最终selection/detail状态 | input→handler、submit、GPU completion、结构计数 |

### 4.3 timestamp与present修正

为避免readback把测量变成同步微基准，应将timestamp query改为**多帧ring**：第`n`帧写query，第`n+K`帧只读取availability已完成的query；报告query availability延迟但不让读回阻塞被测帧。[2] [3] 保留当前`event-to-submit`计时，但增加明确的 `input_to_handler_ns`、`handler_to_submit_ns`、`gpu_command_region_ns` 和 `submit_to_fence_ns` 字段；四者绝不相加伪装成input-to-present。

物理显示延迟需要另一条证据链。若平台可提供presentation timing，可报告其为`presented`而非photon；若要宣称input-to-photon，必须使用显示器光敏器/高帧率相机等外部测量。Xvfb数据只能保留为无显示链路的CI/协议回归。

### 4.4 GPUI公平比较协议

Noir与GPUI须运行在同一物理机器、同一GPU、同一window system、同一分辨率/scale/refresh、同一font/文本、同一输入脚本、同一preload/warm-up状态。若GPUI不能在同一Vulkan backend提供相同粒度的timestamp，报告应拆分为：**公共端到端CPU/semantic指标**与**框架内部可观测GPU指标**；不要把Noir的GPU timestamp与GPUI的handler日志并列比较。

建议每个workload做至少200个有效样本，分成至少3个独立session，按 `Noir→GPUI` 与 `GPUI→Noir` 交替顺序运行以抵消温度、频率和cache漂移。报告中位数、P95、P99、IQR、每项原始样本及语义checksum；只在置信区间/重复session都支持时讨论差异。任何一方发生adapter、font、backend或present-mode不一致时，结果应降级为“实现观察”，不得称作框架胜负。

## 5. 立即可执行的修正清单

| 优先级 | 操作 | 预期产物 |
|---:|---|---|
| P0 | 将当前llvmpipe registry/profile明确改名或标注为软件adapter专用 | 防止真实GPU错误采用llvmpipe cost model。 |
| P0 | 固定并保存当前滚动summary；将旧报告的6.283/6.526 ms标为历史样本，不与当前6.604/6.597 ms混用 | 报告可追溯性。 |
| P0 | 在所有报告标题标出指标边界：`event-to-submit`、`GPU command region`、`X11 endpoint excluding present` | 消除“GPU frame time”误读。 |
| P1 | 在Host加入延迟query ring与per-frameJSONL | 消除同步readback对生产路径的污染。 |
| P1 | 为真实GPU运行calibration matrix：warm-up 20、samples 200，生成独立registry/manifest | 获得可用的device-specific成本模型。 |
| P1 | 把10k list、scrollbar和四键导航纳入matrix | 让校准覆盖当前框架真实优势路径。 |
| P2 | 对GPUI实现相同语义checksum和统一输入workload | 得到真正可比较的应用级对照。 |
| P2 | 单独建设physical-present测量 | 只有完成后才讨论用户感知延迟。 |

## References

[1]: [Mesa LLVMpipe documentation](https://docs.mesa3d.org/drivers/llvmpipe.html)  
[2]: [Khronos Vulkan timestamp query sample and guidance](https://docs.vulkan.org/samples/latest/samples/api/timestamp_queries/README.html)  
[3]: [wgpu `QueryType::Timestamp` documentation](https://docs.rs/wgpu/latest/wgpu/enum.QueryType.html)  
[4]: [Noir virtual-list scroll and GPUI comparison report](VIRTUAL_LIST_SCROLL_GPUI_COMPARISON_REPORT.md)  
[5]: [Noir fusion performance quantification report](FUSION_PERFORMANCE_QUANTIFICATION_REPORT.md)  
[6]: [Raw llvmpipe wgpu benchmark JSON](out/wgpu-benchmark.json)  
[7]: [Current llvmpipe-specific calibration registry](profiles/registry.json)  
[8]: [Raw Noir/GPUI scroll summary and samples](wgpu-verify/out/noir-gpui-virtual-list-scroll-summary.json)  
[9]: [Raw Noir/GPUI input summary](wgpu-verify/out/noir-gpui-virtual-list-input-summary.json)  
[10]: [Noir calibration freshness gate report](CALIBRATION_FRESHNESS_GATE_REPORT.md)
