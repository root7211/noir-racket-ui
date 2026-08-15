# Noir 桌面组件宏系统 v1 交付报告

**状态：已实现并验证**  
**范围：`app-shell`、`surface`、`toolbar`、`table-header`、`status-pill`、`detail-panel`**

## 结论

Noir 现在拥有第一组可复用桌面chrome组件，但这些组件不是运行时widget。它们由 `#lang noir/ui` 的宏解析器在展开期立即lower为既有 `column`、`stack`、`text` 和 `button` primitive；导出的Scene、Rust宿主和WGSL中没有组件tag、组件对象、virtual tree、运行时token查询或组件dispatch。

> **组件宏只压缩源码；运行时继续执行同一份固定Scene、slot、glyph placement、tile mask和worklist。**

## 宏与lowering

| 宏 | lower后的基础节点 | 必须显式保留的ID | 运行时新增路径 |
|---|---|---|---|
| `app-shell` | `column` | root ID | 无 |
| `surface` | `stack` | surface ID | 无 |
| `toolbar` | `stack` + 静态比例`text` | root / text ID | 无 |
| `table-header` | `stack` + 静态比例`text` | root / text ID | 无 |
| `status-pill` | `stack` + `button` + 静态比例`text` | root / button / label ID | 仅复用既有button action slot |
| `detail-panel` | `stack` + 动态legacy `text` | root / detail text ID | 仅复用既有动态glyph patch |

`toolbar`和`table-header`要求调用者显式声明`#:font-face`，因此page-2字体资源仍须经既有font asset与font placement proof准入。`detail-panel`要求静态`#:max-chars`，故详情文本仍是固定glyph地址范围。`status-pill`要求显式button和label ID，确保应用级activation plan引用的节点不会在组件内部变成不可见的运行时身份。

## 两个应用迁移

日志浏览器和实时监控表格已迁移到组件宏表达，而其核心列表与交互ABI不变。

| 应用 | 已迁移chrome | 明确保留的不变量 |
|---|---|---|
| `examples/log-browser.rkt` | app shell、toolbar、table header、list surface、detail panel、append status pill | `system-log`、`log-detail`、`append-tail`、`append-tail-label`、row activation、scrollbar、row ring |
| `examples/realtime-monitor.rkt` | app shell、toolbar、table header、list surface、detail panel、refresh status pill | `telemetry-grid`、`monitor-detail`、`refresh-telemetry`、数值data-register、可见性分流、row activation |

## 等价性与真实验证

新增 `examples/desktop-components-primitive.rkt` 和 `examples/desktop-components-macros.rkt`。两者表面语法不同，但在移除只用于来源追溯的build attestation后，导出Scene完全一致；比较范围包含布局、字体资产、font placement、glyph placement、event map、state/action plan、tile、worklist与所有ABI contract。迁移后的日志浏览器和监控表格也分别与迁移前Scene等价。

| 验证入口 | 结果 | 覆盖范围 |
|---|---|---|
| `./tools/verify_desktop_component_macros.sh` | PASS | Racket测试；手写primitive与macro fixture严格Scene等价；组件tag不泄漏 |
| `./tools/verify_font_placement_scene.sh` | PASS | page-2比例字体proof、face/UV篡改拒绝、真实X11/Vulkan首帧 |
| `./tools/verify_log_browser.sh` | PASS | tail append、End、选择、详情、Enter激活、真实X11/Vulkan |
| `./tools/verify_realtime_monitor.sh` | PASS | 数字/字母glyph域、可见性分流、arena-only零GPU写入、真实X11/Vulkan |

为避免遗留Xvfb进程导致偶发冲突，font placement回归已改为扫描连续空闲display组，而不是依赖PID取模的固定display编号。

## 开发者用法

```racket
(app-shell #:id monitor-shell
  (toolbar #:id monitor-app-bar #:text-id monitor-title
           #:label "REALTIME MONITOR TABLE" #:font-face noir-desktop-sans-18)
  (table-header #:id monitor-columns-bar #:text-id monitor-columns
                #:label "STATE HOST CPU MEM NET LAT JIT" #:font-face noir-desktop-sans-18)
  (surface #:id monitor-list-shell #:height 84 #:background (theme-color panel) #:clip true
    ;; existing virtual-list remains untouched
    ...)
  (detail-panel #:id monitor-detail-panel #:text-id monitor-detail
                #:dynamic monitor-detail-damage #:max-chars 29)
  (status-pill #:id monitor-refresh-bar #:button-id refresh-telemetry
               #:label-id refresh-telemetry-label #:button-label "REFRESH BATCH"
               #:label "REFRESH FIXED BATCH" #:font-face noir-desktop-sans-18
               #:on open-monitor-detail #:background (theme-color accent)))
```

完整语法、默认token和禁止的运行时行为见 [DESKTOP_COMPONENT_MACROS_V1.md](DESKTOP_COMPONENT_MACROS_V1.md)。

## 下一步

现在两个数据密集型示例都消费同一编译期桌面chrome语言。下一阶段应将这一实践扩展到**有界动态终端视图或设置面板**之前，先补充组件宏的编译期诊断与更完整的`surface/card`组合约束；不得为了组件可组合性重新引入运行时组件树。 
