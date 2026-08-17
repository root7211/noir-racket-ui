# Material Observability Workbench Plan v1 — Delivery Report

**Status:** delivered and regression-verified
**Author:** Manus AI
**Reference application:** `examples/material-observability-workbench.rkt`

## Executive summary

`material_observability_workbench_plan v1` turns Noir's previously separate Material navigation, 10,000-row virtual-list, detail panel, restricted deployment overlay, modal focus graph, and focus-ring renderer into one closed desktop workbench. The compiler emits three resident views—Overview, Systems, and Alerts—together with their immutable surface, glyph, Event Map, shadow, and tile ownership sets. At runtime, rail selection changes only precomputed alpha lanes and one fixed local tile mask; it neither builds a page nor discovers descendants.[1]

The completed reference workbench proves that Noir's compile-first model can span more than a single component. It holds one mutable Systems arena of 10,000 logical records backed by four physical rows, while the two other views, dialog, menu, and focus rings remain static compiler artifacts. The workbench thereby provides a representative desktop-scale integration target rather than another isolated micro-feature.[1] [2]

## Delivered implementation

| Layer | Delivered result |
|---|---|
| Example application | `material-observability-workbench.rkt`: desktop-wide Material workbench with one rail, three view endpoints, one Systems list, detail panel, and deployment overlay |
| Racket ABI | `material_observability_workbench_plan` object-or-false Scene field; required gate; schema/revision contract; root-first subtree witnesses |
| Compiler lowering | rail-to-view binding, resident view preservation during static occlusion planning, precomputed instance/glyph/event/tile sets, Systems list anchor |
| Rust proof | ABI gate, navigation pairing, subtree/resource/tile verification, unique Systems `10000 × 4` proof, shadow ownership proof |
| Runtime executor | first-present hiding of noninitial endpoints; old/new view alpha exchange; local no-packets tile union; pointer and list-input active-view gates |
| Visual integration | existing modal focus ring remains independently preallocated and works above the active Alerts endpoint |
| Test tools | structural oracle, one-command X11/Vulkan regression, four-mode Scene mutation generator, visual screenshots and review notes |

## Compiler product and bounded runtime work

The reference Scene freezes three view values and one list ownership relation.

| Endpoint | View root | Resident role | Runtime transition work |
|---:|---|---|---|
| `0` | `overview-view` | static health and render-budget summary | hide previous endpoint, restore Overview endpoint, redraw existing local tile |
| `1` | `systems-view` | only mutable 10,000-row data arena | restore fixed four-row viewport, detail surface, glyphs, and shadows |
| `2` | `alerts-view` | static alert posture and deployment guard | hide Systems alpha lanes and block list input before presenting Alerts |

The final X11/Vulkan run logged `37` hidden surface-instance lanes and `263` hidden glyph lanes for the two noninitial views. The Overview → Systems transition wrote `38` surface alpha lanes, `345` glyph alpha lanes, and `10` shadow alpha lanes; the Systems → Alerts transition wrote `37`, `263`, and `10` lanes respectively. These counts are compile-derived endpoint set sizes, not runtime scene traversal results.[3]

> The key result is not that every transition has the same number of writes. It is that every write address and every transition-specific count belongs to the emitted Scene before the first input event.

## Startup proof and rejection coverage

The host accepts a workbench only after reconstructing the compiler's static facts. Four deliberate corruptions were generated from the canonical Scene and rejected during startup.

| Mutation | Corruption | Required rejection evidence |
|---|---|---|
| `offset` | alters the first view's `QuadInstance` address | instance address set no longer equals the canonical subtree |
| `node` | replaces a Systems node witness with a forged node | canonical static subtree witness invalid |
| `tile` | changes Alerts tile range | tile scope no longer equals canonical subtree union |
| `disable` | replaces the plan with `false` while retaining the required flag | required workbench plan may not be disabled |

This coverage matters because the runtime alpha executor trusts its precomputed addresses. The startup proof prevents a Scene from widening or redirecting that write set through a forged JSON artifact.[2] [4]

## Real X11/Vulkan evidence

The one-command regression launched the release host under Xvfb with `WGPU_BACKEND=vulkan` and supplied real pointer and keyboard input. The evidence directory contains the exact rendered states.

| Evidence | Interaction | Verified result |
|---|---|---|
| `01-overview-initial.png` | first present | Overview alone is visible; Systems and Alerts resident resources are hidden |
| `02-systems-active.png` | rail click | Systems table, scrollbar, detail surface, and append action appear |
| `03-systems-list-navigation-selection.png` | PageDown + row click | fixed list navigation and physical-row selection update execute |
| `04-alerts-active.png` | rail click | Alerts alone is visible; Systems surface/glyph/shadow resources are absent |
| `05-overlay-initial-focus.png` | deployment click | dialog, scrim, menu, and Deploy focus ring appear over Alerts |
| `06-overlay-tab-focus.png` | Tab | outline moves Deploy → Cancel through two fixed alpha patches |
| `07-overlay-closed-alerts-active.png` | Escape | overlay and ring are cleared; Alerts is restored without residual artifact |

The host log additionally shows a `material-workbench list-input-gated` record while Alerts is active, proving that hidden Systems list navigation is rejected before it can mutate the data arena.[3] [5]

## Regression status

| Check | Result |
|---|---|
| Racket macro and language suite | `Noir Cost Model language checks passed.` |
| Workbench Scene structural oracle | `material_observability_workbench_plan v1 structural oracle: PASS` |
| Rust 1.87 release build, wgpu 30 / winit X11 | passed |
| Real X11/Vulkan rail, list, overlay, focus-ring flow | passed |
| Four startup-time Scene tampering cases | all rejected |
| Existing rounded surface two-application suite | `ROUNDED_SURFACE_PLAN_V1_REGRESSION: PASS` |
| Combined command | `MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_V1_REGRESSION: PASS` |

Run the complete suite with:

```bash
bash tools/verify_material_observability_workbench_plan_v1.sh
```

## Design implications and next boundary

This milestone establishes a stronger framework-level claim than the individual component plans: static GUI subsystems can share one Scene, one state-slot space, and one GPU lifetime without being merged into a generic dynamic widget runtime. The workbench's rail is still a finite transition table; the list is still a fixed physical arena; modal focus remains a finite subgraph; and each GPU write remains locally witnessed.[1] [2]

The next appropriate extension is **workbench-local measurement and workload comparison**, not immediate generalization. The workbench now supplies a representative target for a replay matrix that can compare Overview rail switches, Systems page/selection transitions, Alerts gates, and overlay focus transitions on the same real GPU. General routing, multiple data arenas, and arbitrary nested overlays should remain out of scope until a new closed-world proof contract is designed.

## References

[1]: ./MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_V1.md "Material observability workbench plan v1 ABI"
[2]: ./noir/ui/main.rkt "Noir UI compiler source"
[3]: ./out/material-observability-workbench-evidence/x11-vulkan.log "Workbench real X11/Vulkan runtime trace"
[4]: ./tools/mutate_material_observability_workbench_scene.py "Workbench Scene mutation generator"
[5]: ./out/material-observability-workbench-evidence/VISUAL_CHECKS.md "Workbench visual review record"
