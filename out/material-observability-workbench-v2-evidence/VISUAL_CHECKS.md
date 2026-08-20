# Material Observability Workbench v2 — X11/Vulkan Visual Checks

The following images were captured from the real X11/Vulkan host after the v2 startup proof admitted the compiled Scene.

| Evidence | Checked state | Visual result |
|---|---|---|
| `01-overview-initial.png` | Initial endpoint | Overview is visible while the Systems and Alerts resident endpoints are hidden by their precomputed alpha lanes. |
| `02-systems-data-active.png` | Overview → Systems; PageDown and row selection | The 10,000 × 4 Systems arena, its scrollbar, selected row and Systems detail panel are visible. |
| `03-alerts-data-active.png` | Systems → Alerts; Alerts PageDown and row selection | The separate 2,048 × 3 Alerts arena is visible with its own three physical rows, scrollbar and `DETAIL INFO SELECTED` detail output. Systems content is absent. |
| `04-overlay-initial-focus.png` | Alerts endpoint; deploy overlay opened | The dialog/scrim is layered over the Alerts endpoint and the first preallocated blue rounded focus outline is visible. |
| `05-overlay-tab-focus.png` | Alerts endpoint; modal Tab | The focus outline has moved to Cancel without affecting the Alerts list or dialog text layers. |
| `06-overlay-closed-alerts.png` | Escape close | The scrim, dialog and focus ring are removed; the Alerts endpoint remains visible. |

The checked screenshots establish the intended visual layering. The runtime log separately records the fixed Systems and Alerts PageDown paths and their independently selected logical rows.

> The visible text is intentionally constrained to the existing fixed-cell uppercase domain for the dynamic table and detail data path.
