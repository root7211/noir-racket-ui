# Noir Visual Language v2 — Iteration Notes

## Real X11/Vulkan review

Reviewed:

- `out/log-browser-visual-language-v2.png`
- `out/realtime-monitor-visual-language-v2.png`

The structural direction is correct: both applications now have a persistent product rail, a distinct page header, a summary strip, a table card, a separate context card, and one compact primary action. Page-3 tabular text now uses true fixed 10 px cell geometry, so table rows are dense and aligned rather than stretched across the card.

The first visual pass is not yet acceptable. Shared defects are:

1. Page-2 display/title/value text is oversized. The current font-scale multipliers compound with node height, causing titles and metric values to collide with neighbouring regions.
2. Surface values are authored as sRGB-looking hex values but rendered as linear colour, so cards and rails appear much brighter than intended. The v2 palette must use lower encoded values.
3. Table title and column label occupy the same vertical band. The card title must be smaller and the column band must begin lower.
4. Dynamic detail text still uses the legacy page-0 path and overlaps the context title. It must be isolated below a fixed detail heading or hidden until a later dynamic-detail typography plan.
5. Semantic row tints are too bright and opaque over a large area. Warning/error/info colours must become low-luminance opaque tints because the current quad renderer does not use their alpha as a compositing tint.
6. Primary action labels extend beyond the button. Button text scale must be reduced and the fixed width increased or label shortened.

## Next iteration constants

- Static page-2 scales: meta `0.70`, body `0.78`, title `0.95`, display `1.10`; do not exceed `1.10` in this iteration.
- Use much lower encoded dark values: canvas approximately `#020306`, rail `#05070B`, surface `#090C12`, raised surface `#0D111A`.
- Table card: title height 28, column band begins at y=44, list begins at y=78.
- Row tints: info around `(0.025 0.040 0.065 1)`, warning `(0.11 0.075 0.018 1)`, error `(0.13 0.025 0.040 1)`, debug `(0.055 0.040 0.090 1)`.
- Detail card title remains page 2; legacy dynamic detail begins at least 42 px below it and uses a dedicated local frame.
- Primary action uses a short label (`APPEND`, `REFRESH`) and page-2 scale no greater than `0.78`.

## Final log-browser review

The final log-browser pass is visually coherent and usable. The persistent rail, 76 px page header, four summary tiles, table card, independent column band, fixed-cell body and context card now read as one desktop system. No static text overlaps. The page-3 rows keep true 10 px advance and the empty detail state no longer emits a wall of zero glyphs. The primary action is contained within its button.

The remaining verification item is the monitor frame: warning/error tints must remain distinguishable without dominating the table, and its shared chrome must match this final log-browser hierarchy.

## Final monitor review

The final monitor frame matches the log-browser visual grammar. Warning and error rows remain immediately distinguishable, but the lower encoded tint values keep data text dominant. The fixed page-3 tabular body is crisp and aligned, while page-2 chrome supplies a clear display/title/meta hierarchy. The empty detail card and compact `REFRESH` action are visually balanced. This pass is accepted as the v2 screenshot baseline.
