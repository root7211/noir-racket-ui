# Noir Counter：局部 GPU 更新验证记录

## 已验证的端到端路径

本实验已经完成以下闭环：

```text
#lang noir/ui
  state:  frame-rate = 60
  action: refresh-data => frame-rate += 84
  binding: fps 动态文本，#:max-chars 3

       ↓ 宏展开

Scene JSON
  action.refresh-data.writes[0] = add(frame-rate, 84)
  action.refresh-data.gpu_updates[0] =
    glyph node=fps, state=frame-rate, offset=0, byte_length=96, glyph_count=3

       ↓ wgpu host

初始写入 glyph-buffer 的 [0, 96) → 离屏渲染前帧
只写入 glyph-buffer 的 [0, 96) → 离屏渲染后帧
```

该路径不是依靠运行时遍历 UI tree 找到 `fps`；`fps` 的节点 ID、绑定状态、glyph 数、字节偏移和写入长度在 Racket 宏展开期已生成。

## 动作语义与 GPU 审计

| 项目 | 编译产物或观测结果 |
|---|---|
| 初始状态 | `frame-rate = 60` |
| 动作 | `refresh-data` |
| 状态写入 | `frame-rate += 84` |
| 后继状态 | `frame-rate = 144` |
| 动态节点 | 1 个：`fps` |
| glyph 许可证 | 3 个 glyph |
| glyph buffer 计划区间 | `[0, 96)` 字节 |
| 动作后 instance-buffer 写入 | **0** |
| 动作后 glyph-buffer 写入 | **1 次：`(0, 96)`** |
| 共享 render pipeline | 1 条 |
| 前帧 checksum | `31,687,392` |
| 后帧 checksum | `32,313,024` |

## 视觉工件检查

前帧与后帧均为真实 wgpu/Vulkan 离屏纹理 readback。两帧的根容器、标题区域、行容器、静态标签和按钮区域保持相同；只有左侧的动态 `fps` tile 从绿色变为青色。这种变化由 shader 从同一 GPU glyph storage buffer 读取 3 个数值 slot 得到。

| 初始帧：`60` | 动作后：`144` |
|---|---|
| ![before](out/noir-counter-before.png) | ![after](out/noir-counter-after.png) |

当前 shader 用“数字 glyph slot → 颜色”的可视编码来避免把实验复杂度提前转移到完整字体系统。它已证明真正的 GPU storage range update 能改变局部 visual output；下一阶段只需把这条数据路径替换为 glyph atlas UV/quad instance，而不改变 `offset + byte_length` 的语言与运行时契约。

## 结论

> `refresh-data` 后，系统没有重建 Scene、没有重新写入 instance buffer、没有创建新 pipeline，也没有修改任何声明之外的 glyph storage；它只向 compiler 指定的 `[0, 96)` 区间提交一次 `queue.write_buffer`，并产生可测、可见的帧差异。

这就是 Noir 的第一个可执行核心命题：**一次小的状态变化，被编译为一次小的 GPU 数据变化。**
