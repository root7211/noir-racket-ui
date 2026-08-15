# Noir Font Placement Rendering v1 交付报告

**作者：Manus AI**  
**阶段：桌面视觉系统第三阶段**  
**状态：实现完成，真实 X11/Vulkan 与篡改回归通过**

## 1. 结论

Noir 已从“字体 atlas 已注册但不可采样”推进到**比例字体实际进入 glyph placement 渲染**。应用可以在静态 `text` 节点上显式声明 `#:font-face`；Racket 编译器在宏展开期读取已经验证的 fontc manifest，将字符映射、glyph ID、UV、advance、bearing、基线和 NDC quad 全部固化到 Scene。运行时不执行字体发现、fallback、shaping、UV 查询或几何计算。[1] [2]

本阶段没有改变 `GlyphPlacementInstance = 48 bytes` 的 GPU 实例 ABI。新增的 `face_id` 只作为 Scene 级启动期反向证明字段，完成验证后仍打包为既有 48-byte 实例。因此，字体质量升级没有把字符串、哈希表或字体引擎引入事件热路径。[1] [3]

| 层级 | 本阶段产物 | 运行时剩余工作 |
|---|---|---|
| Racket DSL | 静态 `text` 支持 `#:font-face` | 无字体查询 |
| 编译期 shaping | glyph ID、UV、advance、bearing、baseline、NDC quad 固化 | 无 shaping |
| Scene ABI | `font_placement_plan = noir-font-placement-plan-v1@1` | 仅反序列化与证明 |
| Rust proof | face、page、static-only、glyph domain、UV、advance逐项核验 | 首帧前一次性完成 |
| wgpu 资源 | legacy array atlas 与 page-2 `R8Unorm` atlas进入固定 bind group | 绘制时仅按已固化 page 采样 |
| WGSL | page 0/1 nearest；page 2 R8 linear coverage | 无分支查表与字体状态 |

## 2. Racket 编译器实现

`noir/ui/main.rkt` 增加了 fontc glyph 度量记录、face-aware binding 与独立 font placement contract。`#:font-face` 只允许用于**静态文字**；动态 text-run 继续使用原有固定容量 page 0/1 路径。未知 face、未覆盖字符、越界 glyph 或动态 page-2 使用在宏展开阶段直接拒绝。[1]

对于 page 2，编译器从 manifest 读取 `x/y/width/height`、`advance`、`bearing_x/bearing_y` 与 line metrics。每个字形的 atlas UV、比例推进和屏幕 quad 由编译器确定。legacy 路径保持原有 5×7 atlas 语义，日志浏览器的虚拟列表正文与动态详情仍不承担比例字体 shaping 成本。[1] [4]

日志浏览器当前把以下静态 UI chrome 切换到 `noir-desktop-sans-18`：

| 节点 | 字符串 | 路径 |
|---|---|---|
| 应用栏标题 | `SYSTEM LOG BROWSER` | page 2 比例字体 |
| 表格列头 | `LEVEL TIME SOURCE MESSAGE` | page 2 比例字体 |
| 操作按钮文字 | `APPEND FIXED TAIL` | page 2 比例字体 |
| 虚拟列表正文 | 固定容量日志行 | legacy page 1 |
| 选中详情 | 29-cell 动态 text-run | legacy page 0 |

## 3. Scene ABI 与启动期证明

新增合同与资产合同相互独立：`font_asset_plan v1` 继续证明字节资源注册，`font_placement_plan v1` 专门证明哪些 placement 获准激活 page 2。这样没有修改已经冻结的资产注册语义。[2]

Rust 宿主在创建首帧前执行以下准入：

| 不变量 | 拒绝条件 |
|---|---|
| 合同版本 | schema/revision 不等于 `noir-font-placement-plan-v1@1` |
| face 注册 | page-2 placement 的 `face_id` 未出现在已验证资产表 |
| 静态边界 | page-2 placement 标记为 dynamic |
| page 一致性 | placement page 与 face 的注册 page 不同 |
| glyph domain | 低 16-bit glyph ID 越过 dense manifest domain |
| UV 一致性 | Scene UV 与 manifest rectangle 不一致 |
| advance 一致性 | Scene advance 与 manifest advance 不一致 |
| legacy 隔离 | page 0/1 placement 携带非空 `face_id` |

精确负向回归已经验证：把首个 page-2 placement 的 face 改为 `tampered-font-face` 会在首帧前拒绝；修改其 UV 左边界同样会被 manifest 反向证明拒绝。[3] [5]

## 4. Rust/WGSL 渲染路径

固定 text bind group 同时绑定 legacy `texture_2d_array`、legacy nearest sampler、fontc `texture_2d` 与 fontc linear sampler。WGSL 直接读取实例中已经编译的 `atlas_page`：page 2 从 R8 纹理的红通道取得 coverage，page 0/1 保持原有采样。[3] [6]

真实验证中还发现一个必须显式处理的后端边界：当前适配器报告 `SUBGROUP_VERTEX=false`。GPU compute 写出的多个 indirect glyph 命令读回完全正确，但同一 render pass 的后续 indirect glyph 段在可见帧中丢失。Noir 因此采用**能力驱动兼容执行器**：

| 适配器条件 | 执行方式 |
|---|---|
| page 2 静态 chrome | 固定 compiler-proved direct subrange |
| `SUBGROUP_VERTEX=true` 的 legacy packet | compute worklist → indirect draw |
| `SUBGROUP_VERTEX=false` 的 legacy packet | 同一 compiler-proved direct subrange |

该回退不重新计算范围，也不扫描字符串或节点树；运行时仍消费编译器给出的 `first_placement + lane_count`。它牺牲的是某些后端上的 indirect dispatch 形式，而不是 Noir 的纯数据流与静态地址原则。[3]

## 5. 真实验证结果

| 验证项 | 结果 |
|---|---|
| Racket 全量回归 | PASS |
| Rust 1.87 / wgpu 30 release 构建 | PASS |
| page-2 face 篡改 | 首帧前拒绝 |
| page-2 UV 篡改 | 首帧前拒绝 |
| X11/Vulkan atlas 上传 | 262,144-byte R8 上传通过 |
| page-2 placement proof | 60 glyph 通过 |
| 实际可见比例字形 | 标题、完整列头、按钮文字通过 |
| 真实 End 键 | viewport `0 → 9997` |
| 真实鼠标释放 | 选择 logical row 9998 / physical slot 2 |
| 真实 Enter | row activation 与 coalesced batch 通过 |

最终可见证据位于 [`out/log-browser-ui/15-fontc-page2-compatible-full.png`](out/log-browser-ui/15-fontc-page2-compatible-full.png)。一键回归入口为：

```bash
./tools/verify_font_placement_scene.sh
./tools/verify_log_browser.sh
```

回归脚本不再复用固定的 `:117/:118` display，而是为正向、face 篡改、UV 篡改与交互测试分配隔离的 Xvfb display，并通过 trap 回收全部进程，避免中断后焦点落到旧窗口。[5] [7]

## 6. 重跑性能数据对主线的约束

此前确认性重跑支持一个有限而重要的结论：Noir 的**预编译局部更新 endpoint**在该 AMD 780M/WSL2/Dozen 实验配置中具有稳定的大效应优势；它支持继续投资编译型路径，但不构成通用 GUI、原生显示或 input-to-photon 优势的证明。[8]

本阶段没有把字体 shaping 加入点击热路径。不过，由于宿主现在基于适配器能力选择 direct/indirect glyph executor，下一轮真实 AMD 780M 测量应记录 `SUBGROUP_VERTEX` 能力与实际 executor，再比较新版本；不能直接把旧测量数值当作新提交的性能证明。

## 7. 下一步主线

字体资产已经完成“生成 → Scene注册 → 启动期证明 → 实际采样”的闭环。按照既定战略，下一步不应继续扩大底层证明系统，而应实现**实时监控表格示例**，复用已经冻结的 virtual list、data update batch、selection、row activation、scrollbar 与 navigation ABI，同时使用本阶段比例字体渲染静态 chrome。完成第二个用户可见示例后，再集中修复列表行视觉、surface/card/toolbar 内联组件宏，并冻结桌面视觉 ABI。

## References

[1]: noir/ui/main.rkt "Racket compiler and font-aware placement lowering"
[2]: FONT_PLACEMENT_PLAN_ABI_V1.md "Font Placement Plan ABI v1"
[3]: wgpu-verify/src/bin/noir_winit_host.rs "Rust host proof and renderer integration"
[4]: examples/log-browser.rkt "Log browser hybrid typography example"
[5]: tools/verify_font_placement_scene.sh "Font placement end-to-end regression"
[6]: wgpu-verify/src/host_placement.wgsl "Legacy and fontc atlas sampling shader"
[7]: tools/verify_log_browser.sh "Real X11 log browser interaction regression"
[8]: data/rigorous-20260815-221938/CONFIRMATORY_RERUN_AUDIT_20260815.md "Confirmatory rerun session-aware audit"
