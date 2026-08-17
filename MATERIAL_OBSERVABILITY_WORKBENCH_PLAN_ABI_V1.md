# Material Observability Workbench Plan v1

**Status:** frozen v1 interface
**Owner:** Manus AI
**Scope:** a compiler-proved integration plan for one Material rail, three resident views, one 10,000-row Systems arena, and the existing restricted deployment overlay.

`material_observability_workbench_plan v1` is not a general runtime router. It declares a closed desktop workbench whose view topology, resource addresses, alpha endpoints, Event Map membership, and tile scope are all emitted by `#lang noir/ui` before the host starts. The host may only select an already-proved endpoint; it never allocates a view, discovers a descendant, recomputes geometry, or scans a component tree at interaction time.[1]

## 1. ABI identity and Scene contract

| Item | Frozen value |
|---|---|
| Schema | `noir-material-observability-workbench-plan-v1` |
| Revision | `1` |
| Scene field | `material_observability_workbench_plan` |
| Required gate | `material_observability_workbench_required` |
| Initial view | `initial_view` / `initial_value` |
| Fixed topology | one rail, exactly three resident views |
| Data arena rule | exactly one Systems `virtual_list`; capacity `10000`, physical slots `4` |
| Routing model | rail action → proven view endpoint; no runtime route lookup |

The plan field is either a JSON object that conforms to this document or JSON `false`. A scene with `material_observability_workbench_required: true` **must** carry the object. The host rejects a missing or disabled plan before renderer initialization.

```json
{
  "material_observability_workbench_required": true,
  "material_observability_workbench_plan": {
    "abi_schema": "noir-material-observability-workbench-plan-v1",
    "abi_revision": 1,
    "id": "observability-workbench",
    "rail_id": "observability-rail",
    "state": "workbench-view",
    "state_index": 2,
    "systems_list_id": "observability-log",
    "systems_view_id": "systems-view",
    "initial_view": "observability-overview",
    "initial_value": 0,
    "views": []
  }
}
```

## 2. Fixed view endpoint record

Each entry in `views`, in declaration order, has the following required fields.

| Field | Meaning | Host proof obligation |
|---|---|---|
| `destination_id` | navigation rail destination identifier | equals the same-index navigation-selection destination |
| `event_slot` | fixed rail Event Map index | belongs to the destination action and is unique across views |
| `target_value` | state slot endpoint | equals the declaration index: `0`, `1`, or `2` |
| `view_root_id` | root static stack identifier | is the first node witness and is a static `stack` layout node |
| `node_ids` | root-first canonical static subtree witness | root first; remaining IDs strictly lexical and present in the compiled layout |
| `instance_offsets` | 44-byte `QuadInstance` source addresses | equals exactly the view subtree's layout offsets; nonempty and cross-view disjoint |
| `instance_alphas` | initial alpha endpoint for each instance | finite, `[0,1]`, and cardinality-matched to offsets |
| `glyph_slots` | 48-byte glyph placement slots | equals exactly the view subtree's glyph placement slots; nonempty and cross-view disjoint |
| `event_slots` | descendant interactive Event Map entries | equals exactly the subtree event slots and is cross-view disjoint |
| `tile_ids` | static redraw scope | equals the canonical union of render tiles intersecting view resources |

> The source of truth for all address sets is the emitted static subtree, not a permissive rectangle containment test. Geometry is used only as an additional tile-scope witness.[1]

In the reference fixture, declaration order is fixed as follows.

| Value | `destination_id` | `view_root_id` | Runtime role |
|---:|---|---|---|
| `0` | `observability-overview` | `overview-view` | static system and render-budget summary |
| `1` | `observability-systems` | `systems-view` | sole mutable 10,000-row data arena and detail panel |
| `2` | `observability-alerts` | `alerts-view` | static alert posture and deployment guard |

## 3. Compiler lowering requirements

The top-level restricted declaration has one rail reference, one Systems list reference, three static view roots, and an initial destination. During lowering, the compiler verifies that the rail has exactly three destinations, the referenced roots are distinct static stacks, and every root is a resident node. Resident nodes are preserved through static occlusion/tile planning: view alpha switching is lawful only because the renderer plan retains every endpoint even when it begins hidden.[1]

The compiler emits both standard `navigation_selection_plan v1` and this integration plan. It does not emit a second navigation state machine. The workbench plan binds the existing rail state slot to view-specific, immutable alpha sets.

## 4. Startup-time host proof

Before allocating a usable render path, the Rust host verifies the ABI revision and required gate, then proves the following invariants.

| Proof stage | Rejected condition |
|---|---|
| ABI gate | wrong schema or revision, required plan omitted, non-object payload |
| rail pairing | `rail_id`, state slot, destination IDs, event slots, or target values differ from `navigation_selection_plan` |
| subtree witness | root ordering invalid, non-root node IDs unordered, unknown node, or root not a static stack |
| resource set | declared instance offsets, alpha endpoints, glyph slots, or Event Map slots diverge from the view subtree |
| ownership | an instance, glyph slot, event slot, or shadow layer is claimed by more than one view |
| tile scope | declared tiles differ from the canonical static subtree union |
| Systems anchor | the referenced list is unique, belongs to `systems_view_id`, has capacity `10000`, and has four physical slots |
| shadow endpoint | every shadow layer sourced by a view offset is mapped to that view with its compiler-defined opacity |

The proof yields a compact runtime table consisting of the selected view index, three view endpoint records, a fixed `event_slot → view_index` map, the Systems list index, and precomputed tile masks. Raw JSON is not consulted on pointer, keyboard, scroll, or rail paths after this point.[2]

## 5. Runtime execution model

### 5.1 Initial endpoint

Immediately after static resource preparation and before first present, the host writes alpha `0` to every noninitial view's proven `QuadInstance` alpha lanes, glyph placement alpha lanes, and independent shadow instance alpha lanes. It performs no layout, packet-plan, or tile-plan calculation.

### 5.2 Rail transition

A verified navigation event first updates the normal rail colors. The workbench executor then performs a fixed alpha endpoint exchange:

1. old view `instance_offsets` → alpha `0`;
2. old view `glyph_slots` → alpha `0`;
3. old view shadow indices → alpha `0`;
4. new view `instance_offsets` → their compiled `instance_alphas`;
5. new view `glyph_slots` → alpha `1`;
6. new view shadow indices → their compiler-defined opacity;
7. old and new tile masks are OR-ed into the existing no-packets local render request.

Only the compiler-proved old/new lanes are written. No dynamic visibility traversal, route object, shader recompilation, or global redraw policy is introduced.[2]

### 5.3 Input isolation

The `event_slot → view_index` table gates pointer hit testing: an event owned by a hidden view cannot be selected. The Systems list is additionally gated across hover, row selection, row activation, Arrow navigation, PageUp/PageDown/Home/End, and wheel scrolling. A non-Systems endpoint causes these paths to return without mutating the virtual-list arena.[2]

Global rail and restricted overlay entries remain outside view-specific event ownership. The overlay continues to use its existing binary visibility plan, modal focus subgraph, and independent focus-ring visual plan.[3]

## 6. GPU resource rules

The plan introduces **no new dynamic buffer class**. It reuses three already frozen resource representations.

| Resource | ABI | Visibility write |
|---|---:|---|
| surface instance | `QuadInstance`, 44 bytes | `color.a` at byte `offset + 28` |
| static glyph placement | `GlyphPlacementInstance`, 48 bytes | `alpha` at byte `slot × 48 + 44` |
| elevation shadow instance | `QuadInstance`, 44 bytes | `color.a` at `shadow_index × 44 + 28` |

The focus ring remains a separate preallocated outline pass, controlled only by the modal focus visual plan. It is not duplicated per workbench view.[3]

## 7. Explicit non-goals

Version 1 intentionally excludes arbitrary route trees, user-created pages, multiple mutable lists, dynamic resource discovery, runtime view compilation, focus restoration across view removal, generic accessibility graph generation, and unconstrained nested overlays. These are not implementation omissions: excluding them preserves the closed-world proof and bounded write-set model.

## References

[1]: ./noir/ui/main.rkt "Noir UI compiler: workbench lowering, resident-view retention, Scene serialization"
[2]: ./wgpu-verify/src/bin/noir_winit_host.rs "Noir wgpu host: workbench ABI gate, proof, alpha patches, and input gates"
[3]: ./MODAL_FOCUS_VISUAL_PLAN_ABI_V1.md "Modal focus visual plan v1 ABI"
