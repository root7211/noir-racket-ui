# EUI-NEO视觉参考审计（阶段性记录）

**来源仓库：** https://github.com/sudoevolve/EUI-NEO
**查看资产：** `docs/pic/1.jpg`、`docs/pic/2.jpg`

## 可移植视觉原则

| 观察 | EUI-NEO中的表现 | 对Noir的可编译转译 |
|---|---|---|
| 明确的应用骨架 | 固定侧栏、宽主内容区、大圆角主surface | 编译期固定`navigation rail + content canvas`两栏几何，不做运行时reflow |
| 大尺度分组 | 标题、说明、section标题、控件组之间有明显垂直节奏 | 引入12/16/24/32px离散spacing阶梯和section frame宏 |
| 对比而非装饰建立层级 | dark主题使用近黑canvas、深灰surface、细边框和高亮蓝 | 将canvas/surface/raised/border/accent定义为对比度有序的静态RGBA token |
| 控件变体清晰 | filled、outline、ghost三类按钮具有明显但统一的状态语言 | 为`status-pill`/button增加编译期variant，不在运行时解析style字符串 |
| 边框与圆角一致 | sidebar item、card、content frame使用统一圆角与1px边界 | 固定8/12/18px radius阶梯；用现有quad/radius与额外border quad lower |
| 强主色有限使用 | 蓝色只用于选中导航、标题强调、focus/active状态 | accent只用于关键交互与选中，不用于大面积普通row背景 |
| 卡片内部有二级结构 | 图表卡片有标题、divider、内容与说明 | 将表格主区、detail区、指标条设计为独立编译期surface section |
| 排版层级 | display标题、section标题、正文和辅助文字尺寸/颜色明显分离 | 使用page 2 fontc静态文字的display/title/meta层；page 3仅承担数据正文 |
| 状态反馈具物理感 | hover、press、focus通过填充、边框和亮度变化表达 | 继续复用固定hover/pressed多字段patch，新增variant对应静态颜色组 |
| 内容占满画布 | 主surface在可用窗口内形成完整信息架构，不留下大片无语义空区 | 重构两个示例为侧栏/主卡片/详情栏或状态栏，而不是单列内容停在上半屏 |

## 不应照搬

EUI-NEO的阴影、任意动画、运行时组件与全量控件体系不应直接搬入Noir。Noir v2只采用可被编译成固定quad、颜色、边框、字体placement和有限状态patch的视觉规则；模糊阴影、动态样式查找与运行时布局仍不进入热路径。

## 源码级证据

EUI-NEO的主题系统不是随意挑色，而是把排版、spacing、radius和control size分成离散阶梯。其默认spacing从1、2、4、6、8、10、12、16、20、24、30、40到48px，radius从2、4、6、8、10、12、14、16、18、22到full；dark主题使用约`#1A1A1F` canvas、`#26262E` surface、`#404047` hover surface、`#595961` active surface、白色正文、`#4D4D4D` border与`#3871E0`主accent。[1] EUI组件层仍只组合row、column、stack、rect、text等DSL图元，而不是建立第二套渲染器；组件要求稳定ID并以派生子ID保持结构可追踪。[2]

Card默认使用20px内容inset、18px section radius、1px低不透明边框和panel shadow；Button将normal/hover/pressed、border、radius与press scale组织成一个样式结构，并在内部lower为`Stack + Rect + Row + Text`。[2] Noir可以移植前四项，但v2暂不实现模糊shadow；改用第二层外框quad和轻微明度差表达elevation。

## References

[1]: https://github.com/sudoevolve/EUI-NEO/blob/main/components/theme.h "EUI-NEO theme tokens"
[2]: https://github.com/sudoevolve/EUI-NEO/blob/main/docs/%E7%BB%84%E4%BB%B6.md "EUI-NEO components documentation"
[3]: https://github.com/sudoevolve/EUI-NEO "EUI-NEO repository and preview gallery"
