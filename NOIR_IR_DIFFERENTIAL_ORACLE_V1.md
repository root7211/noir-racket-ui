# `noir-ir` 与 Scene Differential Oracle v1

## 目标

v1为Rust迁移建立**可执行等价性基线**，而不是重写Racket宏、布局器或wgpu宿主。Racket仍是唯一Scene生产者；新的`noir-ir` crate读取其JSON Scene，并把应用层workbench的可证明子集转换为稳定、强类型、可canonical比较的Rust IR投影。

> v1的问题不是“Rust能否反序列化JSON”，而是“Rust端看到的容量、owner、action、状态域、固定地址和tile写集是否与Racket输出逐项相同”。

## Crate 边界

`noir-ir`是独立的Rust 1.87 library + CLI crate，不依赖`wgpu`、`winit`或X11。它只依赖`serde`、`serde_json`和`anyhow`，因此可作为未来Rust编译器、lint工具和宿主共享的纯IR基础。

| v1包含 | v1明确不包含 |
|---|---|
| Scene JSON读取、ABI contract投影、双data-view workbench、跨视图确认事务、确认行bitset计划 | Racket宏重写、完整布局树、字体atlas加载、GPU资源、事件循环、wgpu渲染。 |
| canonical JSON、结构验证、projection diff、golden fixture校验 | 自由JSON重排容错、语义猜测、动态组件树或自动修复非canonical Scene。 |

## Canonical Projection

差分投影仅包含已经冻结且决定应用层业务语义与固定写集的字段：

| 区域 | 比较字段 |
|---|---|
| ABI | `scene_abi`；workbench、cross-view transaction、acknowledged row state的schema/revision。 |
| Workbench | ID、rail、初始view、三枚ordered view、两枚ordered data-view及其list/owner/capacity/slot/辅助计划ID。 |
| Transaction | source/target、action/state/slot/event、Alerts颜色lane、detail glyph范围、Overview计数glyph范围、tile范围。 |
| Row state | state domain、Alerts owner、capacity、word bits/count、确认action、颜色/detail恢复地址与tile范围。 |

所有数组保持编译器声明的语义顺序；无序映射使用`BTreeMap`输出。输出JSON使用单一Rust serializer格式。差分工具不比较原始Scene全文，避免将非迁移目标的font哈希、渲染诊断或键序变化误报为语言迁移错误。

## Racket / Rust Oracle

每次回归由同一应用层源码执行两个独立投影：

1. Racket exporter加载刚导出的Scene，并用`tools/export_noir_ir_projection.rkt`写出受限canonical投影；
2. `noir-ir` CLI加载同一Scene，构造强类型IR后输出Rust canonical投影；
3. CLI `diff`比较两个投影，并拒绝任何字段、顺序、容量、地址或tile差异；
4. 标准与compact profile各保留一份版本控制的golden canonical JSON，防止Racket与Rust同时发生同向错误而没有可审计基线。

## 迁移原则

未来Rust compiler pass必须先输出与该投影等价的Scene子集，才能替代相应Racket pass。任何新计划都应先被添加到`noir-ir`的投影和差分oracle，再进入Rust前端迁移。这样，迁移进度以**可验证的语义覆盖**衡量，而不是按重写代码行数衡量。

## 后续阶段

v1之后依次扩展：`noir-ir`完整workbench资源范围；Rust profile lowering；Rust应用层`noir-workbench/app`等价前端；最后才考虑替代Racket默认前端。Racket在每一阶段保留为golden compiler，直到全部目标计划均有双编译器差分覆盖。
