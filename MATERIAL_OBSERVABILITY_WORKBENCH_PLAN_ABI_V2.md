# Material Observability Workbench Plan ABI v2

**Status:** Frozen v2 interface
**Owner:** Manus AI
**Scope:** A compiler-proved Material workbench with one rail, three resident views, two restricted compact data arenas, and the existing restricted deployment overlay.

`material_observability_workbench_plan v2` is a closed Scene integration contract. It evolves v1 by replacing the unique Systems-list assumption with exactly two declaration-ordered data views. It does **not** introduce runtime routing, list discovery, dynamic allocation, geometry computation, or mutable view topology. The compiler emits the complete ownership and redraw relation before host startup; the host only selects already-proved state endpoints and writes pre-addressed lanes.[1]

## 1. ABI identity and Scene gate

| Item | Frozen value |
|---|---|
| Schema | `noir-material-observability-workbench-plan-v2` |
| Revision | `2` |
| Scene field | `material_observability_workbench_plan` |
| Required gate | `material_observability_workbench_required` |
| Resident topology | one rail and exactly three views |
| Data topology | exactly two declaration-ordered compact arenas |
| Routing model | rail action → proven alpha endpoint; no runtime route lookup |

The plan field is either a conforming JSON object or JSON `false`. When `material_observability_workbench_required` is `true`, `false` is rejected before a usable renderer state is established. Version 1 Scene objects are deliberately not accepted by this ABI gate because their single-list proof is weaker than the two-arena ownership contract.

```json
{
  "material_observability_workbench_required": true,
  "material_observability_workbench_plan": {
    "abi_schema": "noir-material-observability-workbench-plan-v2",
    "abi_revision": 2,
    "id": "observability-workbench",
    "rail_id": "observability-rail",
    "state": "workbench-view",
    "state_index": 3,
    "initial_view": "observability-overview",
    "initial_value": 0,
    "views": [],
    "data_views": []
  }
}
```

## 2. Resident view endpoint contract

`views` retains the v1 three-endpoint form. Its declaration order is fixed and pairs directly with the `navigation_selection_plan` destination order.

| Value | Destination | View root | Runtime role |
|---:|---|---|---|
| `0` | `observability-overview` | `overview-view` | Static summary; no data arena is admitted. |
| `1` | `observability-systems` | `systems-view` | Owns the Systems data arena. |
| `2` | `observability-alerts` | `alerts-view` | Owns the Alerts data arena and may host the deployment overlay. |

Every view contains root-first `node_ids`, canonical `QuadInstance` offsets, initial alpha endpoints, glyph slots, descendant Event Map slots, and canonical render tile IDs. The Rust proof requires exact equality with the compiler-emitted static subtree. Surface, glyph, event, and shadow ownership are pairwise disjoint across resident views.[1] [2]

## 3. `data_views` record

`data_views` is ordered and has exactly two entries. Each record binds one compact virtual-list arena to one already-proved resident endpoint.

| Field | Meaning | Host proof obligation |
|---|---|---|
| `id` | Stable data-view identifier | Unique and in declaration order. |
| `list_id` / `list_index` | Fixed virtual-list identity and dense host index | Resolves to the same compiled virtual list. |
| `view_id` | Owner resident view root | Resolves to one view and is unique among data views. |
| `logical_capacity` | Logical data capacity | Equals the virtual-list plan exactly. |
| `physical_slots` / `visible_rows` | Fixed recycle and visible slot counts | Equal the virtual-list plan exactly. |
| `scrollbar_id` | Fixed scrollbar companion | Refers to one scrollbar with the same `list_index`. |
| `navigation_id` | Fixed PageUp/PageDown/Home/End companion | Refers to one navigation plan with the same `list_index`. |
| `log_browser_id` | Fixed detail and append companion | Refers to one log-browser plan with the same `list_index`. |
| `row_activation_action` | Fixed selected-row action | Equals the source row-activation plan for `list_id`. |
| `node_ids` | List-root-first static subtree witness | Is canonical and is a subset of the owner view witness. |
| `instance_offsets` / `glyph_slots` / `event_slots` | Data-arena resource witnesses | Equal the list subtree resource sets; never alias the other arena. |
| `tile_ids` | Local redraw domain | Equals the canonical workbench render-tile intersection for the list subtree. |

The reference workbench freezes the following tuple.

| Data view | Owner view | Capacity | Physical slots | Visible rows | Fixed list |
|---|---|---:|---:|---:|---|
| `systems-data-view` | `systems-view` | 10,000 | 4 | 4 | `observability-log` |
| `alerts-data-view` | `alerts-view` | 2,048 | 3 | 3 | `observability-alert-stream` |

The host rejects a different tuple. This is a deliberately bounded component capability, not a generic multi-list container.

## 4. Compiler lowering

The restricted top-level declaration is:

```racket
(material-observability-workbench
 #:id observability-workbench
 #:rail observability-rail
 #:data-views ((systems-data-view observability-log systems-view)
               (alerts-data-view observability-alert-stream alerts-view))
 #:views ((observability-overview overview-view)
          (observability-systems systems-view)
          (observability-alerts alerts-view)))
```

During lowering, `#lang noir/ui` proves the three rail endpoint records first. It then proves each declared data view against a static `virtual-list`, a compact data-register table, exactly one scrollbar plan, exactly one navigation plan, exactly one log-browser plan, and the list's `on-activate` action. It exports list-root-first resource witnesses and computes the data tile set against the **workbench** render schedule. This distinction prevents private virtual-list tile numbering from leaking into the host redraw ABI.[1]

Resident view nodes are retained through compile-time occlusion planning. Therefore hidden views are still valid fixed alpha endpoints rather than lazily built routes.

## 5. Startup-time proof and runtime table

Before rendering, the host validates the ABI gate, rail pairing, state slot, all three view subtrees, alpha endpoints, glyph/event sets, shadows, and tile masks. It additionally validates the two data-view records against virtual-list, scrollbar, navigation, log-browser, and row-activation plans.

| Rejected class | Example rejected mutation |
|---|---|
| Arena address forgery | An Alerts `instance_offsets` entry no longer equals the static list subtree. |
| Owner-subtree forgery | An Alerts witness begins with a Systems node or leaves its owner view. |
| Tile forgery | Alerts `tile_ids` differ from the canonical list-subtree render-tile union. |
| Required-gate bypass | A required Scene changes the plan object to JSON `false`. |
| Auxiliary-plan mismatch | A data view points at another list's scrollbar, navigation, log-browser, or row action. |

Successful proof produces view endpoint records, `event_slot → view_index`, `list_index → owner_view_index`, and two precomputed data tile masks. Pointer, keyboard, wheel, Page navigation, selection, row activation, and scrolling do not inspect JSON or search a tree after this point.[2]

## 6. Fixed runtime execution

A rail transition retains the v1 fixed alpha exchange: old surface, glyph, and shadow lanes are hidden; the new view's compiler-defined alpha endpoints are restored; the union of old/new view tile masks is redrawn with the pre-admitted no-packets path.

Input admission is now owner-based. A list path is allowed only when:

```text
owner_view_for_list[list_index] == selected_view_index
```

Thus Overview owns no list and PageDown returns without an arena update. Systems PageDown consumes only `observability-list-navigation`. Alerts PageDown consumes only `observability-alert-list-navigation`. Overlapping on-screen list geometries are safe because pointer row resolution filters by active owner **before** calculating the logical row.

The deployment overlay, its modal focus subgraph, and its independent SDF focus-ring pass remain global restricted plans. They do not allocate a second overlay or duplicate focus ring resources per data view.[3]

## 7. GPU resource rules and non-goals

The workbench still introduces no dynamic buffer class. It reuses preallocated `QuadInstance` alpha lanes, static glyph placement alpha lanes, fixed shadow alpha lanes, and the existing compact glyph-ID patch paths for row content and detail panels.

Version 2 intentionally excludes arbitrary numbers of lists, runtime-added views, dynamic list ownership, shared mutable row arenas, runtime-generated routes, unconstrained data schemas, generic viewport nesting, and dynamically discovered focus graphs. Adding any of these requires a new ABI revision and a new proof model.

## References

[1]: ./noir/ui/main.rkt "Noir UI compiler: workbench v2 parsing, dual data-view lowering, resident-view retention, and Scene serialization"
[2]: ./wgpu-verify/src/bin/noir_winit_host.rs "Noir wgpu host: v2 ABI gate, dual-arena proof, alpha endpoint execution, and owner-view input admission"
[3]: ./MODAL_FOCUS_VISUAL_PLAN_ABI_V1.md "Modal focus visual plan v1 ABI"
