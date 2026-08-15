# Noir UI → wgpu：Counter 增量更新验证

本目录验证的不是“能否用 wgpu 画几个矩形”，而是 Noir 的核心路径：**一条声明式 action 被编译为一次确定的 GPU buffer-range 写入。**

```text
#lang noir/ui
  state:  frame-rate = 60
  action: refresh-data => frame-rate += 84
  binding: fps 动态文本，#:max-chars 3

      ↓ Racket 宏展开与 JSON 导出

action.refresh-data.gpu_updates[0]
  kind        = glyph
  node        = fps
  state       = frame-rate
  offset      = 0
  byte_length = 96
  glyph_count = 3

      ↓ Rust/wgpu host

初始 glyph-buffer 写入 [0, 96) → 渲染 60
动作后 glyph-buffer 写入 [0, 96) → 渲染 144
```

## 哪些部分是真实 wgpu 工作

| Noir 产物 | wgpu 后端行为 |
|---|---|
| `instance_capacity = 6` | 创建一次 `VERTEX | COPY_DST` instance buffer，并仅在初始阶段写入。 |
| `glyph_capacity = 3` | 创建一次 `STORAGE | COPY_DST` glyph buffer，总大小为 96 字节。 |
| `gpu_update(offset=0, byte_length=96)` | action 后唯一一次 `queue.write_buffer(&glyph_buffer, 0, payload)`。 |
| 6 个 Scene node | 由一条共享 instance-driven quad pipeline 绘制。 |
| glyph storage | WGSL fragment shader 从 storage buffer 读取 3 个数字 slot，因此写入真正改变像素输出。 |
| 离屏 target | Vulkan/llvmpipe 下创建 `Rgba8Unorm` 纹理，渲染、回读并导出 PPM/PNG。 |

实验故意不为每个 node 创建 shader、pipeline、uniform buffer 或 bind group。所有节点复用**一条** pipeline；action 后也不重新写入 instance buffer。

## 已验证结果

```text
Noir Counter → wgpu incremental verification
  scene nodes     : 6
  instance budget : 6 (used 6)
  glyph budget    : 3
  global glyph steps: 1
  exact bindings  : [("fps", 0, 96)]
  adapter         : llvmpipe (LLVM 20.1.2, 256 bits) (Vulkan, Cpu)
  state transition: frame-rate 60 → 144
  action          : refresh-data
  post-action instance writes: 0
  post-action glyph writes   : [(0, 96)]
  shared pipelines : 1
  before checksum  : 31687392
  after checksum   : 32313024
```

前后 checksum 不同，且两个 PNG 工件可直接比较：只有动态 `fps` tile 的颜色编码改变；容器、静态标签、按钮和所有几何实例保持不变。

| 初始状态：60 | action 后：144 |
|---|---|
| ![before](out/noir-counter-before.png) | ![after](out/noir-counter-after.png) |

## 运行方式

```bash
cd noir-racket-ui
export PLTCOLLECTS="$PWD:/usr/share/racket/collects"
racket tools/export-dashboard.rkt out/counter.scene.json

mkdir -p /tmp/noir-wgpu-runtime
chmod 700 /tmp/noir-wgpu-runtime
cd wgpu-verify
XDG_RUNTIME_DIR=/tmp/noir-wgpu-runtime \
WGPU_BACKEND=vulkan \
cargo run --release -- ../out/counter.scene.json out/noir-counter

python3 ../tools/ppm_to_png.py out/noir-counter-before.ppm out/noir-counter-before.png
python3 ../tools/ppm_to_png.py out/noir-counter-after.ppm out/noir-counter-after.png
```

## 边界与下一步

本实验使用一个极小的 host layout，并用“数字 slot → 颜色”可视化动态 glyph 内容，避免将核心验证混入字体 shaping/atlas 复杂度。因此它证明的是**精确状态 → 精确 GPU storage range → 可见帧差异**，不是完整文字渲染器或硬件性能 benchmark。

下一步应保持相同的 `gpu-update(offset, byte_length)` 契约，替换为真实 glyph atlas UV、glyph quad instance 与 batch-range 更新。随后增加第二个动态 node，验证两个独立状态各自拥有不重叠 buffer range，进一步证明 Noir 的因果依赖图能在 GPU 侧保持可分离性。

## 参考

[1] [wgpu 官方网站](https://wgpu.rs/)
