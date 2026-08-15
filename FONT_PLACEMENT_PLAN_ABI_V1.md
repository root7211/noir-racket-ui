# Font Placement Plan ABI v1

## Purpose

`font_asset_plan v1` proves and registers an immutable fontc R8 atlas. It deliberately remains `registered-inactive`; it does not authorize any glyph placement to sample that atlas. `font_placement_plan v1` is the separate activation contract for compiler-emitted proportional static text.

> The runtime must never derive glyph metrics, UV rectangles, face fallback, text shaping, or atlas addresses. A page-2 placement is a fully compiled draw record whose only runtime task is to sample its immutable atlas rectangle.

## Contract

The Scene field `abi_contracts.font_placement_plan` is required and must equal:

| Field | Required value |
|---|---|
| `schema` | `noir-font-placement-plan-v1` |
| `revision` | `1` |

Each `glyph_placement_plan[]` entry gains nullable field `face_id`.

| Placement class | `atlas_page` | `face_id` | `dynamic` | Texture source |
|---|---:|---|---:|---|
| Legacy digit | 0 | `null` | permitted | legacy `texture_2d_array` layer 0 |
| Legacy ASCII | 1 | `null` | permitted where legacy ABI allows | legacy `texture_2d_array` layer 1 |
| fontc proportional | 2 | required, exact asset face ID | `false` | immutable R8 `texture_2d` registered by `font_asset_plan v1` |

For page 2, `glyph_id` is encoded as `(2 << 16) | manifest_glyph_id`. `manifest_glyph_id` must be in the asset's dense glyph domain. The compiler computes `atlas_uv` exactly as:

```text
[x / atlas_width, y / atlas_height, width / atlas_width, height / atlas_height]
```

where `x`, `y`, `width`, and `height` are from the verified font manifest glyph record. The compiler uses manifest advance and bearing metrics to make the NDC quad a fixed proportional placement. The GPU instance ABI remains **48 bytes**; `face_id` is startup-proof metadata and is not uploaded per instance.

## Startup proof

Before resource creation or the first render, Rust must verify every page-2 placement against the verified font asset:

1. `face_id` exists and identifies the unique registered asset for page 2.
2. The placement is static (`dynamic == false`).
3. The encoded page and glyph domain agree with the asset manifest.
4. Its UV rectangle exactly matches the manifest glyph rectangle within float serialization tolerance.
5. Its advance matches the manifest advance within float serialization tolerance.
6. Pages 0 and 1 do not carry `face_id`; page 2 cannot use the legacy texture array.

A rejected proof is a startup error, never a runtime fallback.

## Rendering rule

The text bind group has immutable legacy page 0/1 resources plus one immutable page-2 R8 view and filtering sampler. The fragment shader selects its sampler solely from compiler-fixed `atlas_page`; it has no runtime face lookup, atlas search, shaping, or buffer-range recomputation.

## Deliberate v1 boundary

This contract enables only static proportional text. Dynamic text registers, virtual-list row recycling, user input, and fallback shaping remain on their existing frozen legacy paths. They must not emit page-2 placements until a later dynamic font placement contract introduces fixed glyph domain and update rules for those paths.
