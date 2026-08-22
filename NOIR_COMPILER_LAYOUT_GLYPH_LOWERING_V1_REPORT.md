# `noir-compiler` Layout and Glyph Summary Lowering v1 — Delivery Report

**Author:** Manus AI

**Status:** Implemented and verified

**Scope:** The second pure Rust lowering pass in Noir's staged frontend migration.

## Result

`noir-compiler` now extends the closed application-profile input of the first pass with a second, renderer-independent lowering result: `ProfileLayoutGlyphProjection`. The pass starts only from the stable application ID and `standard | compact` profile; it neither accepts arbitrary geometry nor consumes renderer addresses. Its output combines the already-validated profile semantics with a small, auditable set of layout and glyph-budget constraints.

| Contract area | Frozen result |
|---|---|
| Canvas and rail | `1280 × 720` canvas; rail `(32, 32, 180, 656)` |
| Resident views | Overview, Systems, and Alerts each at `(236, 104, 996, 560)` |
| Data viewports | Alerts `(256, 182, 956, 96)`; Systems height `128` for `standard` and `96` for `compact` |
| Acknowledged-count endpoint | `(260, 228, 238, 40)`, eight glyphs, page `1`, stride `32` bytes |
| Glyph summary | Non-null face set, atlas-page set, total placements, and dynamic placements |

The profile-dependent glyph facts are deliberately finite and exact.

| Profile | Total placements | Dynamic placements | Acknowledged first byte | Acknowledged last byte |
|---|---:|---:|---:|---:|
| `standard` | 487 | 290 | 2464 | 2688 |
| `compact` | 463 | 258 | 2720 | 2944 |

The Racket Scene truth for the acknowledged-count endpoint requires a deliberate ABI detail: its eight dynamic page-1 glyphs expose JSON `null` for `face_id`. The Rust endpoint therefore stores `face_id: Option<String>` and expects `None`; it does not fabricate a desktop face identity. The separately validated glyph summary still contains the two non-null faces, `noir-desktop-sans-18` and `noir-table-body-mono-16`, as well as pages `1`, `2`, and `3`.

## Equivalence Method

For each existing application-layer fixture, Racket first produces the authoritative complete Scene. `tools/export_noir_compiler_layout_glyph_plan.rkt` then independently extracts the profile semantics, key rectangles, glyph summary, and acknowledged-count byte-range endpoint. Rust produces the competing result with the closed command:

```text
noir-compiler lower-layout-glyph APP_ID standard|compact OUTPUT
```

`noir-ir diff-layout-glyph` parses both results as `ProfileLayoutGlyphProjection`, validates each projection against the finite profile contract, and only then accepts structural equality. This prevents a pair of identically malformed JSON documents from passing by coincidence.

## Verification

The checked-in regression is:

```bash
bash tools/verify_noir_compiler_layout_glyph_lowering_v1.sh
```

It performs the following sequence in a clean output directory:

| Step | Evidence established |
|---|---|
| Rust tests and release builds | Both renderer-independent crates build under Rust 1.87 and their unit tests pass. |
| Racket full-Scene export | The `standard` and `compact` application fixtures remain the independent oracle. |
| Double lowering and diff | Racket projection and Rust `lower-layout-glyph` output agree for both profiles. |
| Closed-input rejection | Unknown profile and invalid application ID are rejected. |
| Geometry negative control | Changing Systems viewport height from `128` to `127` is rejected before equality. |
| Glyph negative control | Changing acknowledged-count `glyph_count` from `8` to `7` is rejected before equality. |

A successful run emits:

```text
NOIR_COMPILER_LAYOUT_GLYPH_LOWERING_V1_REGRESSION: PASS
```

The milestone was also cross-checked against the existing first-pass profile regression so the expanded shared `noir-ir` crate does not weaken the earlier semantic equivalence contract.

## Boundaries and Next Step

This is intentionally **not** a general Rust layout engine or text renderer. Racket remains the authority for the complete component tree, Material layout decisions, individual glyph placements, shaping, UVs, advances, NDC positions, clipping, font atlas construction, tile allocation, buffer offsets, and GPU resources. The new Rust pass owns only the closed profile-derived geometric and glyph-summary subset that can be made finite, proven, and independently compared today.

The appropriate successor is another narrow, differentially checked lowering boundary—not a destructive replacement. Any future migration of placement records or text resources should first define a finite canonical projection, have Racket export it from the full Scene, and require a Rust lowering to match it before a renderer consumes it.
