# Subgroup Variant Selection + Differential Oracle

**作者：Manus AI**

## 目标

本阶段在 GPU-driven Packet Activity → Indirect Draw 之上增加变体选择与差分准入。Racket 把 scalar/subgroup 的共同执行契约写入 Scene；Rust 只在 adapter capability 与 WGSL frontend 都可用时选择 subgroup pipeline；启动期以 GPU readback 比较 selected/reference 两套 pipeline 的 activity 与 indirect outputs。

该设计的核心是：**变体只能替换 lane reduction 实现，不能改变 packet descriptor、activity word、indirect command、first placement 或 tile semantics。**

## 编译期 Variant Contract

Racket 新增 `packet-activity-contract` runtime artifact。Command Palette Scene 固定导出以下属性。

| 字段 | 固定值 | 含义 |
|---|---:|---|
| `packet_count` | 4 | 与 Subgroup Packet Plan 长度一致 |
| `workgroup_size` | 32 | scalar/subgroup 两个 WGSL backend 的共同工作组形状 |
| `scalar_entry` | `packet_activity` | portable workgroup-reduction shader entry |
| `subgroup_entry` | `packet_activity_subgroup` | ballot variant shader entry |
| `differential_required` | `true` | Host 必须在准入时比较两个 output ABI |

Racket static oracle 验证该 contract、packet lane mapping、activity word offset 与 16-byte indirect offsets 共同成立。

## Rust Variant Selection

Rust 选择条件是双 gate：

```text
selected = Subgroup
  iff adapter exposes Features::SUBGROUP
  and current WGSL frontend accepts subgroup source
else Scalar
```

两种资源创建函数使用相同的 `GpuPacketDescriptor`、activity storage、indirect storage、bind-group layout 与 32-workgroup dispatch。唯一变化是 shader source 与 entry point。

| Variant | WGSL | 当前 wgpu 0.20 状态 |
|---|---|---|
| Scalar | `host_packet_activity.wgsl` | 已执行 |
| Subgroup | `host_packet_activity_subgroup.wgsl` | 源码已提供，受 language gate 禁用 |

测试显示当前 llvmpipe adapter 虽报告 `Features::SUBGROUP`，但 wgpu 0.20 打包的 Naga WGSL parser 尚不能解析 `enable subgroups;`。因此 selector 明确输出 `variant=Scalar, adapter-subgroup=true, wgsl-subgroup=false`。这不是把 subgroup variant 静默降级，而是一个可审计的 toolchain gate。

## Differential Oracle

启动期创建 selected pipeline 和独立 scalar reference pipeline。二者对同一 glyph storage 与同一 compiler packet descriptors 分别 dispatch，随后把 activity buffer 和 indirect buffer copy 到 MAP_READ buffers。Host 逐字节比较：

| 输出 | 字节数 | 比较语义 |
|---|---:|---|
| activity masks | `packet_count × 4` | 每 packet active lane mask 完全相同 |
| indirect commands | `packet_count × 16` | vertex/instance/first vertex/first instance 完全相同 |

任何 mismatch 都拒绝 host 启动。当前可执行设备上的 self-differential 日志为：

```text
packet-activity-differential: selected=Scalar reference=Scalar packets=4 activity+indirect=equal
```

未来当 language gate 开启时，同一 oracle 将直接比较 `selected=Subgroup` 与 `reference=Scalar`，无需改变 Racket Scene ABI 或 render submission。

## 验证

真实 X11/wgpu 验证通过以下路径：启动 contract proof、scalar differential readback、GPU packet activity compute、tile/full indirect draw、`GPU → Enter` fixed command match 与 Action Slot dispatch。Racket 全量回归结果为 `0` 个 `FAILURE`；Rust release build 通过。

```bash
cd /home/ubuntu/noir_review/noir-racket-ui
PLTCOLLECTS="$PWD:" racket tests/run.rkt
cd wgpu-verify && cargo build --release --bin noir_winit_host
cd .. && tools/verify_gpu_packet_activity.sh
```

## 后续硬件准入

在升级到支持 WGSL subgroup syntax 的 wgpu/Naga toolchain 后，只应切换 `subgroup_wgsl_supported` 的 capability probe，而不应改变 compiler packet contract。首次启用必须保留 differential oracle，并验证至少一个动态 ASCII packet、一个空 dynamic packet、一个 static packet 及 tile-clipped packet 的 activity/indirect outputs。
