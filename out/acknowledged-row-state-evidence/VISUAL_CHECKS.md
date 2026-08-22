# Acknowledged Row State Executor v1 — Visual Checks

## 01 — Alerts acknowledgement

The real X11/Vulkan screenshot shows the Alerts resident endpoint as active. The selected first visible row is highlighted through the admitted fixed color lane, and the Alerts detail endpoint reads `DETAIL INFO ACKNOWLEDGED`. The dialog-free workbench surface, rail, list scissor, detail panel, and Acknowledge control remain visually stable.

## 02 — Recycle restoration

After the integration path performs `PageDown` followed by `Home`, the real X11/Vulkan screenshot again shows the first Alerts logical record as highlighted and the same `DETAIL INFO ACKNOWLEDGED` status. This is consistent with restoration from the fixed logical-row bitset rather than an additional acknowledgement transaction.

## Status

The corresponding host log asserts a single successful transaction (`state=0=>1`), an acknowledged recovery lane for logical row 0, and a later `already-acknowledged` zero-write gate. Screenshot `03-overview-count-once.png` is retained for the fixed Overview count endpoint validation.

## 03 — Overview count once

After the retained Alerts selection is gated outside its owner view, the Overview endpoint is active and its fixed dynamic count glyph range visibly renders `00000001`. The result is consistent with one successful `open → acknowledged` transition; no second increment is present.
