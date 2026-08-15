# Compact Data Register Table ABI

## Purpose

A `data-register-table` scales a recycling virtual list to a fixed logical capacity without serializing one full scroll transition per logical viewport. The compiler emits the physical-row geometry once and emits two direction templates. The host may advance an integer viewport cursor only within compiler-emitted bounds; it does not solve layout or search UI nodes.

## Static Artifact

| Field | Meaning |
|---|---|
| `logical_capacity` | Fixed maximum logical records, e.g. 10,000. |
| `register_width` | Fixed uppercase-ASCII byte capacity per record. |
| `register_seed` | Packed/static initial register recipe, not a runtime string parser. |
| `physical_slots` | Fixed GPU row templates, e.g. 4. |
| `visible_rows` | Fixed viewport rows, e.g. 3. |
| `row_instance_offsets` | Physical slot quad positions. |
| `row_glyph_slots` | Physical slot glyph cells. |
| `scroll_template_down/up` | Fixed address lists and Y-values for all physical slots. |
| `slot_selector` | Canonical modulo mapping from viewport cursor to physical slot; compiler and host prove the same formula. |
| `viewport_subrange_template` | Physical row DrawRange/Glyph subrange selector for each `viewport mod physical_slots`. |

## Runtime Path

```text
wheel delta
  → bounded viewport cursor
  → direction template + modulo selector
  → copy one fixed-width logical register into entering physical glyph slots
  → patch physical row Y coordinates
  → submit pre-proved viewport row DrawRanges / glyph subranges
```

No logical UI node, layout object, text shaper, glyph atlas lookup, or damage rectangle is queried at runtime. The only data-dependent operation is a bounded arena copy from `logical_index * register_width` to the compiler-emitted glyph cell offsets of the entering physical slot.

## Proof Boundary

At startup, the host validates capacity relationships, all physical resource ranges, the two direction templates, modulo selector domain, and glyph translation table. In debug/test mode it also recomputes selected logical-to-physical mappings at boundary cases: viewport 0, `physical_slots - 1`, one wrap, and `max_scroll`.

The initial 12-row explicit-transition fixture remains the semantic oracle. The 10,000-row fixture must instead use the compact template ABI; requiring approximately 20,000 full transition objects would be a compiler artifact-size regression rather than a performance feature.
