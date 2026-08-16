# Noir `dynamic_font_cell_plan` v1

**状态：实现契约；与 `font_placement_plan v1` 独立。**

## 1. 目标

`dynamic_font_cell_plan v1` 激活受限tabular-body字体在 **atlas page 3** 的固定data-register cell渲染。它不修改page 2的静态比例字体语义：page 2仍只服务静态标题、列头与chrome；page 3仅服务编译器已证明的列表正文cell。

运行时可变性严格限于：向已经列举的glyph storage word写入 `(3 << 16) | glyph_index`。它不得创建placement、改变page、face、UV、advance、NDC geometry、clip、packet、tile、bind group或字体资源。

## 2. Scene ABI

`abi_contracts`必须增加：

```json
"dynamic_font_cell_plan": {
  "schema": "noir-dynamic-font-cell-plan-v1",
  "revision": 1
}
```

Scene根部必须包含一个非默认的`dynamic_font_cell_plan`对象：

```json
{
  "abi_schema": "noir-dynamic-font-cell-plan-v1",
  "abi_revision": 1,
  "face_id": "noir-table-body-mono-16",
  "manifest_path": "assets/fontc/noir-table-body-mono-16/manifest.json",
  "atlas_path": "assets/fontc/noir-table-body-mono-16/atlas.r8",
  "font_sha256": "…",
  "atlas_sha256": "…",
  "atlas_page": 3,
  "atlas_width": 256,
  "atlas_height": 256,
  "atlas_channels": 1,
  "coverage_policy": "tabular-body-v1",
  "advance_policy": "fixed-tabular",
  "fixed_advance": 10.0,
  "glyph_domain_first": 0,
  "glyph_domain_count": 37,
  "tables": []
}
```

`tables`按`table_id`升序，且每个元素固定：

| 字段 | 不变量 |
|---|---|
| `table_id` / `list_id` | 唯一；必须引用一个已准入compact data-register与virtual list。 |
| `register_width` | 必须等于data-register宽度。 |
| `physical_slots` | 必须等于列表物理row ring容量。 |
| `placement_slots` | 严格升序、无重复；长度必须为`register_width × physical_slots`。 |
| `glyph_word_offsets` | 与placement一一对应，必须等于该placement的固定word offset。 |
| `cell_uv` | 与manifest中glyph 0的page-3资源尺度一致；作为固定cell atlas语义真值。 |
| `cell_advance` | 每项必须为10.0；不得使用`source_advance`。 |
| `tile_ids` / `packet_worklist_index` | 必须等于既有列表可见更新计划；不得扩大更新范围。 |

## 3. 宏展开期准入

应用必须显式声明一项：

```racket
(dynamic-font-cell-asset
  #:manifest "assets/fontc/noir-table-body-mono-16/manifest.json"
  #:atlas "assets/fontc/noir-table-body-mono-16/atlas.r8")
```

然后仅允许指定同一face的data-register：

```racket
(data-register-table #:id telemetry-registers
  #:font-face noir-table-body-mono-16
  #:seed "NOMINAL ALPHA LOW MID LOW FAST LOW")
```

Racket在展开期必须验证安全相对路径、manifest hash、R8长度、`tabular-body-v1` coverage、`fixed-tabular` policy、37个dense glyph、10px统一advance，以及seed/row-template/update literals全部落在域内。

## 4. Rust 启动期反向 proof

Rust必须在任何GPU上传和窗口首帧前重新读取manifest与atlas，验证Scene/manifest hash、page=3隔离、37-glyph domain、所有glyph rect/advance、table/list指向、placement page/face、placement word address、固定quad/UV/advance和tile/worklist不变量。

page 3是唯一允许无state-index `dynamic=true` placement的fontc page，但只在其slot位于`dynamic_font_cell_plan.tables[].placement_slots`时合法。page 2动态placement、page 3静态placement、legacy page 0/1携带face、或不在table枚举中的word地址均须拒绝。

## 5. WGSL 与执行边界

WGSL仅在`dynamic != 0`时读取一个glyph word。若其高16位为3，则使用已经绑定的page-3 texture和manifest-proved UV table；否则page 0/1保留legacy采样。GPU不得由glyph ID自行推导fontc UV；UV表必须作为编译产物固定进入placement或固定table buffer。

第一实现允许将每个受限glyph的UV表作为只读GPU buffer。运行时data update只写glyph ID word，绝不写UV table或placement instance。

## 6. 负例

以下必须在展开期或首帧前拒绝：非域字符、小写字符、page 3 atlas hash不匹配、glyph index ≥ 37、face mismatch、UV或advance篡改、table外word offset、page 3 placement的mutable geometry、用page 2绑定dynamic body cell，或由动态cell扩大tile/worklist。
