# Noir Desktop Component Macros v1

**状态：实现规范**  
**目标：让桌面chrome具有可复用DSL，而不增加运行时组件系统。**

## 核心语义

桌面组件宏只存在于 `#lang noir/ui` 的宏展开阶段。每个组件必须立即lower为已有的 `column`、`stack`、`text`、`button` 与其静态属性；导出的Scene中不得出现组件tag、组件实例表、virtual tree、运行时主题查询或组件dispatch。

> 组件是**编译期语法压缩**，不是运行时对象边界。

| 宏 | 唯一lowering | 运行时新增状态/寻址 | 字体与token规则 |
|---|---|---|---|
| `app-shell` | `column` | 无 | `gap`、`padding`、`background`、`radius`在解析属性时折叠 |
| `surface` | `stack` | 无 | 表面颜色、半径、clip均为静态属性 |
| `toolbar` | `stack` + 静态`text` | 无 | 必须显式`#:font-face`；title glyph placement在编译期确定 |
| `table-header` | `stack` + 静态`text` | 无 | 必须显式`#:font-face`；列头文字为静态比例text-run |
| `status-pill` | `stack` + `button` + 静态`text` | 仅复用button既有event/action slot | 必须显式button与label ID，避免生成不透明运行时身份 |
| `detail-panel` | `stack` + 动态`text` | 仅复用已声明state的glyph patch | `max-chars`固定，detail text ID显式声明 |

## ID与可证明性

组件根ID和所有下级可见/可交互primitive ID必须由调用者显式提供，或依据现有 `component-child-id` 规则由宏在展开期稳定生成。v1对与应用级plan关联的节点采用显式子ID：`toolbar`的`#:text-id`、`table-header`的`#:text-id`、`status-pill`的`#:button-id`与`#:label-id`、`detail-panel`的`#:text-id`。

因此，`log-browser`和`realtime-monitor`中的`log-detail`、`monitor-detail`、`append-tail`、`refresh-telemetry`等冻结plan引用保持不变。组件迁移不得改变virtual-list、row activation、scrollbar、list navigation、font asset或font placement ABI。

## 默认值

| 宏 | 高度 | 背景 | 间距/边距 | 半径 |
|---|---:|---|---|---|
| `app-shell` | 由子项决定 | `(theme-color canvas)` | gap=`sm`，padding=`lg` | `panel` |
| `surface` | 由调用者或子项决定 | `(theme-color surface)` | 无 | `card` |
| `toolbar` | 34 px | `(theme-color header)` | 无 | 无 |
| `table-header` | 24 px | `(theme-color surface)` | 无 | 无 |
| `status-pill` | 30 px | 调用者显式声明 | 无 | 无 |
| `detail-panel` | 34 px | `(theme-color surface)` | 无 | 无 |

所有默认token仍由 `current-static-theme` 在宏展开时解析。没有同一`noir-app`内的`theme`声明时，含token默认值的组件必须失败，而不是让token抵达运行时。

## 回归不变量

组件迁移后必须满足以下条件：导出Scene仅含基础node tag；指定应用计划引用的ID仍存在；page-2 glyph placement的`face_id`、UV、advance和静态性不变；动态detail range、row颜色offset、data-register slot及action tile mask不扩大；Rust宿主不新增组件分支。验证包含Racket宏测试、Scene结构oracle、font placement、log browser、实时监控表格和真实X11/Vulkan截图。 
