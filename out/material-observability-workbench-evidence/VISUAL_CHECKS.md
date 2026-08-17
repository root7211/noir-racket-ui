# Material Observability Workbench v1 — Visual Checks

## Overview initial endpoint

The first real X11/Vulkan frame presents the Material rail, application bar, deployment entry point, Overview cards, rounded surfaces, and elevation shadows. The Systems table and Alerts cards are absent, showing that nonselected resident views are hidden before first present.

## Systems endpoint and fixed data arena

After the Systems rail click, the frame shows the fixed four-row event viewport, column heading, scrollbar, detail surface, and append action. Overview content is absent. The matching runtime trace records PageDown and row-selection paths, confirming that the preexisting 10,000-record arena is active only on this endpoint.

## Alerts endpoint and isolation

After the Alerts rail click, its selected rail indicator and three alert surfaces are visible. The Systems table, detail panel, row glyphs, and elevation shadows are absent. The runtime trace then records a Systems-only list-input gate rejection for PageDown, confirming that the hidden data arena does not accept keyboard navigation.

## Overlay focus visual

The deployment overlay opens above Alerts with the expected scrim, dialog, menu, and blue rounded focus outline around Deploy. One Tab transfers the outline to Cancel, visibly demonstrating the independent outline pass and the fixed two-ring alpha exchange. Escape removes dialog, menu, scrim, focus outline, and overlay shadows without changing the active Alerts endpoint.

The evidence images `01` through `07` correspond in order to these states and are created by `tools/verify_material_observability_workbench_plan_v1.sh`.
