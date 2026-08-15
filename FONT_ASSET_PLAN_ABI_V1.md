# Noir Font Asset Plan ABI v1

`font_asset_plan` 是Noir第二阶段的独立字体资源接口。它注册构建期已经确定的灰度atlas资源，但不修改既有 `glyph-placement`、`virtual-list`、action、tile 或 packet worklist ABI。

## Scene contract

顶层 `abi_contracts.font_asset_plan` 必须精确为：

```json
{"schema":"noir-font-asset-plan-v1","revision":1}
```

每个 `font_assets[]` 条目必须包含：

| 字段 | 类型 | v1 约束 |
|---|---|---|
| `abi_schema` | string | `noir-font-asset-plan-v1` |
| `abi_revision` | integer | `1` |
| `face_id` | string | 非空且在Scene内唯一。 |
| `renderer_kind` | string | `atlas-gray`。 |
| `manifest_path` | string | 相对于Scene JSON的安全相对路径；不得含 `..`。 |
| `atlas_path` | string | 相对于Scene JSON的安全相对路径；不得含 `..`。 |
| `font_sha256` | string | 64位小写hex，必须与manifest一致。 |
| `atlas_sha256` | string | 64位小写hex，必须与manifest和实际R8字节一致。 |
| `atlas_width` / `atlas_height` | integer | 正数；与manifest、R8长度一致。 |
| `atlas_channels` | integer | v1固定为 `1`。 |
| `pixel_size` / `line_height` | integer | 正数；与manifest metrics一致。 |
| `glyph_domain_first` / `glyph_domain_count` | integer | `first=0`，count等于manifest glyph数。 |
| `atlas_page` | integer | v1固定为 `2`；与legacy page 0/1隔离。 |
| `activation` | string | v1固定为 `registered-inactive`，说明资源已GPU上传并通过proof，但现有legacy placement仍使用page 0/1。 |

## 启动期反向 proof

Rust 宿主在创建窗口、surface或任何GPU资源前必须执行下列验证：Scene contract、条目版本、face ID唯一性、路径安全性、manifest schema/revision、manifest字段一致性、atlas SHA-256、R8长度、glyph ID连续domain以及`atlas_page=2`不与legacy pages冲突。随后宿主上传R8字节到单独的immutable `R8Unorm` 2D texture；该texture必须由Host持有，以确保注册资源确实进入renderer生命周期。

`registered-inactive`在v1中是一个重要边界：它避免没有被fontc UV/metrics重lower的legacy `glyph-placement`错误采样真实比例字体。下一阶段只有在编译器为一个placement子集输出相应 `face_id`、fontc UV、glyph ID domain和page 2后，才能将其激活为可绘制后端。

## 篡改拒绝

任何缺字段、schema/revision漂移、hash不符、manifest与Scene参数不符、atlas字节修改、尺寸不符、glyph domain非连续、page冲突或路径逃逸都必须在启动期拒绝。运行时不得通过重算、猜测或fallback接受不一致的资产。
