# Cross-View Transaction Executor Visual Checks

## Run

The captured run launched `material-observability-workbench-v2.scene.json` under Xvfb with the Vulkan backend. It selected the first Alerts logical row, invoked its canonical row activation, and then switched to Overview.

## `01-alerts-after-ack.png`

The **Alerts** rail destination is active. The first visible physical row has the selected blue color, while the fixed detail panel reads `DETAIL WARN SELECTED`. This confirms that the transaction used the admitted Alerts arena and preserved the preallocated detail endpoint rather than creating a new text resource or surface.

## `02-overview-count-after-ack.png`

The **Overview** rail destination is active. The static label `Acknowledged alerts` is followed by an eight-cell preallocated count rendered as `00000001`. Alerts list and detail resources are not visible in Overview. Together with the host log, this is visual evidence that one acknowledged Alerts selection advanced the fixed Overview count endpoint from zero to one.

## Scope

These screenshots validate the fixed executor's successful path only. The corresponding script regression also checks no-selection and wrong-active-view gates as zero-write paths, plus Scene ABI/proof mutation rejection.
