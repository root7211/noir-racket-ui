# Log Browser visual review notes

Reviewed real X11/Vulkan captures on 640×360 Xvfb display.

## Initial state

The title/header/list/detail/button regions are visibly present. The vertical scrollbar is visible on the right of the list. However, all glyph text is horizontally mirrored, so the intended `SYSTEM LOG BROWSER`, column headings, and row records are unreadable. This is a renderer-wide glyph orientation issue, not a log-browser data-flow failure.

## Tail-selected-detail state

The viewport visibly changes after End and the three tail rows obtain distinct background colors, which is consistent with the WARN/ERROR/DEBUG level state and selection overlays. The detail area updates. Nevertheless, text remains mirrored; the selected/hover backgrounds overlap heavily and column separation is weak. Therefore the visual shell demonstrates state propagation, but it is not yet suitable as a human-facing log browser.

## Required visual follow-up

1. Correct glyph quad UV/vertex orientation before judging typography or accessibility.
2. Separate selected and hover colors, preserve level-color as a thin badge/column rather than a full-row background.
3. Add fixed header/background contrast and visible delimiters for the four columns.
4. After correcting the renderer-wide glyph orientation, recapture the same two states before declaring the example user-facing complete.

## Glyph orientation fix verification

`04-glyph-orientation-fixed.png` confirms that the global vertical inversion is fixed: glyph baselines now have the expected top-to-bottom orientation. The sample is still not human-usable. The fixed 3×5 glyphs are too sparse for long labels, yellow glyph color has inadequate contrast on pale header/detail backgrounds, four logical fields are packed into one unstructured string and overflow their visual row, and selected/hover/full-row level colors compete rather than express a clear hierarchy.

The next UI pass must therefore change the application layout and render styling, not merely re-run the glyph fix.

## Text-run geometry fix verification

`06-text-run-fixed.png` confirms that the global 12%-inset overflow is fixed: `SYSTEM LOG BROWSER` is now fully visible and baseline orientation is correct. The dark header, surface, panel and accent hierarchy materially improves contrast.

The visual pass is still incomplete. The column header shows only its left portion in the captured frame, and the detail panel has no visible human-readable selected-row copy despite the injected End/select/Enter sequence. The row text is now less clipped but column boundaries remain implicit. The next investigation must confirm whether the text/tile packet range excludes the tail glyphs and whether the screenshot's click/Enter actually selects a row after the updated y geometry; no claim of human usability should be made until these two visible-state checks pass.

## 5×7 atlas verification

`08-5x7-human-usable.png` materially improves glyph recognizability: the application title and append label are readable and no longer clipped. The remaining major defect is now isolated to static text node quads: row text nodes default to a pale opaque background and visually cover the level/selection row surfaces, producing the white horizontal bands. The glyph data itself is present; the next pass must make unspecified text backgrounds transparent, while retaining explicit `#:background` surfaces for title, header, detail and action-bar text.

## Final visual acceptance

`10-clean-detail.png` is the first accepted human-readable capture. The header reads `SYSTEM LOG BROWSER`; the column header, selected-row summary `DETAIL ERROR SELECTED`, dark level/interaction row surfaces, and `APPEND FIXED TAIL` action label are all visible. The UI intentionally remains a compact 5×7 pixel typeface, but the prior renderer-wide V inversion, right-edge run overflow, opaque row text backing quads, stale no-packets indirect draw, and hidden detail-counter overlap are resolved.

Remaining aesthetic limits are deliberate MVP constraints rather than visibility failures: table columns use compiler-fixed monospace spacing rather than resizable separators, and level identity is represented by fixed row surface colors. These are appropriate follow-up application features, not blockers for current human operation.
