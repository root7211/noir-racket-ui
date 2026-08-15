# Noir 实时监控表格计划 v1

## 目标

实时监控表格是 Noir 的第二个用户可见示例。它**不修改**已冻结的 `virtual_list_plan v1`、`row_activation_plan v1`、`scrollbar_plan v1`、`list_navigation_plan v1` 或 `font_placement_plan v1`；示例以这些产物为唯一运行时接口，验证固定容量、高频数据更新和选择详情能够复用同一编译型执行模型。

## 固定模型

| 项目 | 固定值 |
|---|---:|
| 逻辑容量 | 10,000 行 |
| 物理 ring slots | 4 |
| 可见行 | 3 |
| 行高 | 28 px |
| 每行 register | 32 个字符 |
| 更新边界 | compiler-declared `data-update-batch` 与宿主注入批次 |
| 静态 chrome | fontc page 2 / `noir-desktop-sans-18` |
| 行正文 | 动态 legacy glyph page 0（数字）与page 1（字母/空格） |

记录格式为固定宽度、uppercase ASCII：

```text
STATE HOST CPU MEM NET LAT JIT
WARN BRAVO 081 654 073 019 014
ERROR DELTA 097 882 091 024 021
```

`STATE` 位于记录开头，因此可复用已有 row status color 与selected-row detail路径；数值字段只改变既有动态glyph cell的低成本固定地址写入。

## 编译期计划

编译器确定以下内容：

1. 每个字符在4个物理row slot中的glyph cell地址。
2. 每个字符的合法legacy page：`0..9`编为page 0；`A..Z`和空格编为page 1。
3. 每个bootstrap/refresh batch的逻辑row索引、固定字符串与表register容量。
4. visible与arena-only分流条件、scroll glyph binding、tile和no-packets worklist。
5. 标题、列头、操作标签的fontc page-2 face、UV、advance、bearing与quad。

运行时只接收一个已经验证的字符串批次，将每个字符写到既有glyph ID word；不重做列布局、文本shape、UV计算或row分配。

## 成功标准

1. 初始可见监控记录包含数字且同时采样legacy page 0/1。
2. 可见行刷新只写入对应physical ring slot的32 glyph cells并发出一个合并render request。
3. 不可见行刷新只更新CPU-side compact arena，GPU glyph writes为零。
4. End/row click/Enter仍通过冻结导航、selection和row activation计划。
5. 标题、列头、刷新标签使用已经证明的fontc page-2比例字体。
6. 真实X11/Vulkan回归、Scene篡改拒绝与刷新微基准均可复现。
