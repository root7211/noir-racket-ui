# Application DSL Macro Design v1

## 目标

`#lang noir/ui` 的低层DSL保留为专家层：它允许明确声明状态、action、virtual-list容量、物理槽、row template、log-browser、rail和workbench计划。应用层v1不删除这些原语，而是在其上提供 `noir-workbench/app` 宏，使作者表达业务对象而非渲染器地址。

```racket
(noir-workbench/app
 #:id ops
 #:title "Operations workbench"
 (systems #:seed "INFO  TIME  CORE  STARTUP")
 (alerts  #:seed "WARN  TIME  EDGE  RETRY"))
```

该表单不暴露容量、physical slot、visible row、stable node ID、detail damage state、row action、rail action、glyph address、tile ID或workbench ownership。宏在展开期生成现有 `noir-app` 的受限低层表单，因而复用已有的Racket compiler、Scene ABI、Rust gate和固定执行器。

## 分层

| 层 | 作者写入 | 编译器推导 |
|---|---|---|
| 应用层 | 应用ID、标题、两个领域流和其seed数据；可选profile | 所有内部ID、状态、action、owner view、workbench data view、transaction和资源计划。 |
| Profile层 | `compact` 或默认 `standard` 这种离散策略名 | logical capacity、physical slot、visible row、viewport高度和固定row template数量。 |
| 专家层 | 原有 `noir-app` / `virtual-list` / `material-observability-workbench` | 无；作者显式承担容量与proof约束。 |

## 受限语法与策略

v1只允许一个三视图Material workbench、一个Systems流、一个Alerts流及唯一Alerts→Overview acknowledgement事务。可选 `#:profile compact` 使用较小但仍冻结的容量端点；默认profile为 `standard`。

| Profile | Systems | Alerts | 目的 |
|---|---:|---:|---|
| `standard` | `10,000 × 4` | `2,048 × 3` | 当前经验证的桌面工作台规模。 |
| `compact` | `2,048 × 3` | `512 × 3` | 教学、CI和资源受限环境。 |

profile是编译期离散选择，不是任意数值参数。v1故意拒绝裸`#:capacity`与`#:physical-slots`，防止应用层重新暴露渲染器资源预算。需要新容量端点时，贡献一个命名profile或退回专家层。

## 展开规则

给定应用ID `ops`，宏以卫生方式派生唯一ID，例如 `ops-view`、`ops-alert-ack-count`、`ops-alert-stream`、`ops-alert-detail`、`ops-alert-acknowledge`、`ops-systems-view`和`ops-alerts-view`。状态所有权不由作者指定：rail状态属于workbench，detail状态属于其data view，确认计数属于Overview summary，Alerts确认action属于Alerts逻辑arena。

宏生成的低层计划包括：状态/action、两个list navigation、两个log browser、三view workbench、唯一cross-view transaction、Material rail、Overview计数端点、两个虚拟列表、两张detail card和固定overlay。下游compiler继续从该静态树导出所有glyph、instance、tile、state slot和proof witness。

## 拒绝语义

宏在展开期拒绝重复或颠倒的领域流、未知profile和非字面seed。宏不会猜测任意外部输入容量；所有外部数据以后都必须通过命名bounded source profile接入。若用户需要第三数据arena、不同列模板、第三事务或自由布局，必须使用专家层或未来版本的显式受限应用宏。

## 验证准则

应用层fixture应与现有workbench v2满足相同的双arena、workbench和cross-view transaction结构oracle。其Scene必须保留Systems `10,000 × 4`、Alerts `2,048 × 3`、三个resident view、唯一confirmation action以及固定Alerts→Overview写集；作者源码中不得出现低层容量、物理槽、workbench data-view或transaction声明。
