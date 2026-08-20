# Material Observability Workbench Plan v2 — Delivery Report

**Status:** Implemented and verified
**Owner:** Manus AI
**Reference fixture:** `examples/material-observability-workbench.rkt`

## 1. Delivery summary

`material_observability_workbench_plan v2` extends the earlier three-view Material workbench from one mutable Systems arena to **two isolated, compiler-owned data views**. The workbench remains a closed-world GUI: one predeclared rail selects one of three resident endpoints, while the host applies fixed alpha and glyph-ID writes at precomputed addresses. No route objects, list ownership search, view allocation, runtime layout, or runtime tile construction was introduced.[1] [2]

| Area | Delivered result |
|---|---|
| ABI | `noir-material-observability-workbench-plan-v2@2` with a required Scene gate and ordered `data_views`. |
| Systems arena | `observability-log`, `10000 × 4` logical/physical capacity, four visible rows. |
| Alerts arena | `observability-alert-stream`, `2048 × 3` logical/physical capacity, three visible rows. |
| Isolation | `list_index → owner_view_index` proof and input gate for pointer, keyboard, wheel, selection, row activation, and page navigation. |
| Visual integration | Alerts list, scrollbar, detail panel, Material shadow/surface styling, overlay dialog, and modal focus ring. |
| Regression | Structural oracle, real X11/Vulkan workflow, four hostile Scene mutations, and rounded-surface compatibility. |

## 2. Fixed Scene topology

The reference fixture keeps the v1 rail and resident endpoints, but Alerts changes from static posture content to a second restricted data arena.

| Rail endpoint | Visible work | Admitted data path |
|---|---|---|
| Overview | Static resource/proof summary | None; PageDown is gated before list mutation. |
| Systems | 10,000-row compact observability stream and detail panel | Systems scrollbar, page navigation, selection, activation, append/detail plans. |
| Alerts | 2,048-row compact incident stream and detail panel | Alerts scrollbar, page navigation, selection, activation, append/detail plans. |

The compiler exports the exact `data_views` tuples: `(systems-data-view, observability-log, systems-view, 0, 10000, 4, 4)` and `(alerts-data-view, observability-alert-stream, alerts-view, 1, 2048, 3, 3)`. Each tuple includes fixed list subtree instance/glyph/event witnesses and a workbench-render-tile scope.[1]

## 3. Runtime work contract

The host startup proof converts raw Scene JSON into compact runtime records. Data ownership is not inferred at interaction time; it is the precomputed table below.

| Runtime path | Proven selection | Write scope |
|---|---|---|
| Overview `PageDown` | No owner arena for selected view | No virtual-list transition or GPU arena write. |
| Systems `PageDown` | `list_navigation_plans[systems]` | Systems fixed compact-row patches plus its scrollbar/tile request. |
| Alerts `PageDown` | `list_navigation_plans[alerts]` | Alerts fixed compact-row patches plus its scrollbar/tile request. |
| Row click | Active owner arena only | Selected physical-row color and that arena's detail glyph range. |
| Rail switch | Old/new resident endpoint | Old/new precomputed surface, glyph, shadow alpha lanes and tile-mask union. |
| Overlay `Tab` | Existing modal focus graph | Two preallocated focus-ring alpha patches. |

The visible real-X11 log showed the exact required paths: Systems PageDown `0 → 4` with `observability-list-navigation`, then Alerts PageDown `0 → 3` with `observability-alert-list-navigation`; the selected rows were respectively logical 4 and logical 3. Overview emitted `material-workbench list-navigation-gated ... no-owner-arena`, establishing the inactive-list boundary.[2]

## 4. Verification results

The formal one-command test is:

```bash
bash tools/verify_material_observability_workbench_plan_v2.sh
```

It completed with:

```text
MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_V2_REGRESSION: PASS
```

| Verification layer | Result | Evidence |
|---|---|---|
| Racket macro/language regression | PASS | `Noir Cost Model language checks passed`. |
| v2 Scene structural oracle | PASS | `verify_material_observability_workbench_plan_v2.py`. |
| Rust 1.87 release build | PASS | `noir_winit_host` with wgpu 30. |
| Real X11/Vulkan workflow | PASS | Overview gate, Systems selection, Alerts selection, overlay open/Tab/Escape. |
| Address mutation | REJECTED | Alerts instance address no longer matched its canonical list subtree. |
| Subtree mutation | REJECTED | Alerts owner-node witness was no longer canonical. |
| Tile mutation | REJECTED | Alerts tile set differed from the canonical list-subtree union. |
| Required-plan disable | REJECTED | Required v2 Scene could not carry `false`. |
| Rounded surface compatibility | PASS | Existing dual-application rounded-surface regression. |

## 5. Visual evidence

The committed evidence directory is `out/material-observability-workbench-v2-evidence/`.

| Image | Confirmed result |
|---|---|
| `01-overview-initial.png` | Overview is shown while both resident data endpoints are alpha-hidden. |
| `02-systems-data-active.png` | Systems arena, its compact rows, scrollbar and detail surface are visible. |
| `03-alerts-data-active.png` | Alerts arena is shown independently with three physical rows and its own detail output; Systems is absent. |
| `04-overlay-initial-focus.png` | Overlay opens over Alerts with the initial SDF focus outline. |
| `05-overlay-tab-focus.png` | Tab moves the outline to the alternate modal endpoint. |
| `06-overlay-closed-alerts.png` | Escape clears the overlay and focus ring while retaining the Alerts endpoint. |

The detailed manual inspection record is `VISUAL_CHECKS.md` in the same directory.

## 6. Architectural conclusion

This delivery demonstrates that Noir can compose two distinct interactive data components into one desktop workbench without abandoning its central constraint: **the runtime does not decide which GUI resources exist or where they live**. It selects one of two compiler-proved data arenas according to a fixed rail endpoint and follows pre-addressed patch paths. The second arena is therefore a framework-level integration test, not merely another visual card.

The next logical work is a real-GPU workbench replay matrix that measures Overview gate, Systems navigation, Alerts navigation, rail switching, and overlay focus as a single comparable benchmark family. Additional generality should be postponed until that closed v2 workload has been measured on real hardware.

## References

[1]: ./MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_V2.md "Material Observability Workbench Plan ABI v2"
[2]: ./wgpu-verify/src/bin/noir_winit_host.rs "v2 startup proof, owner-view input gate, compact list execution, and X11/Vulkan host logs"
