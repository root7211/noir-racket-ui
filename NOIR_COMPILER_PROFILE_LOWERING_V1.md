# `noir-compiler` Profile Lowering v1

## 目标

`noir-compiler v1` 是Rust迁移的第一个**纯、封闭、可差分**lowering pass。它接收应用层工作台的稳定应用ID与离散profile，并生成双数据arena、跨视图确认事务和确认行状态域的语义计划。

它不尝试在第一步重写Racket的完整UI树、Material布局、glyph placement或GPU地址分配。那些字段仍由Racket Scene compiler生成并受现有`noir-ir` Scene projection保护。

> v1证明Rust可以复现“应用意图 → 容量/owner/action/state域”的确定性编译决策；它不声称已经生成可渲染的完整Scene。

## 输入

```text
ApplicationInput {
  app_id: Identifier,
  profile: standard | compact,
  alerts_row_state: acknowledged
}
```

应用ID只能由ASCII小写字母、数字和连字符组成，且必须以字母开头。profile是闭合枚举；裸容量、物理槽、owner或GPU地址均不是输入。

## 输出

| 计划 | 标准profile | compact profile |
|---|---:|---:|
| Systems arena | `10,000 × 4` | `2,048 × 3` |
| Alerts arena | `2,048 × 3` | `512 × 3` |
| acknowledged bitset | `32 × u64` | `8 × u64` |
| resident views | Overview=`0`、Systems=`1`、Alerts=`2` | 相同 |
| 跨视图确认 | Alerts → Overview，固定`+1` | 相同 |

输出内的所有ID都以`{app_id}-`卫生派生，例如`operations-alerts-stream`、`operations-acknowledge-alert`和`operations-acknowledged-alert-state`。状态所有权由计划固定：Systems arena归Systems view，Alerts arena和确认bitset归Alerts view，确认计数归Overview。

## 差分策略

Racket侧`tools/export_noir_compiler_profile_plan.rkt`从已导出的应用层Scene提取同一语义投影；Rust `noir-compiler` 从输入直接lower同一投影。`noir-ir diff-profile`读取强类型计划并逐项比较标准和compact两份输出。

这与现有完整Scene oracle互补：完整Scene oracle锁定glyph地址、tile和其他已迁移前端仍未负责的字段；profile oracle锁定Rust首个pass必须等价的业务语义、容量和owner决策。

## 非目标

v1不接收任意文本、外部数据、第三数据arena、自由事务、裸资源预算或未声明状态域。它也不替换Racket宏，更不会跳过Racket/Rust差分就成为默认Scene生产者。
