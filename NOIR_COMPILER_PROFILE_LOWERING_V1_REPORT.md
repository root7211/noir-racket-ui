# `noir-compiler` Profile Lowering v1 — Delivery Report

**Author:** Manus AI
**Status:** Implemented and verified
**Scope:** The first pure Rust lowering pass in Noir's staged frontend migration.

## Result

`noir-compiler` now lowers a closed `ApplicationInput` consisting only of an application ID, `standard | compact` profile, and the implicit `acknowledged` Alerts row-state intent. It emits a strongly typed `ProfileLoweringProjection` shared with `noir-ir`.

The output is deliberately semantic rather than render-complete. It includes the three resident workbench endpoints, two dataarena records, row activation actions, the Alerts→Overview `+1` transaction, and the `open | acknowledged` bitset plan. It does not generate Racket's full static tree, Material layout, glyph locations, tile table, or GPU resources.

| Profile | Systems arena | Alerts arena | Acknowledged table |
|---|---:|---:|---:|
| `standard` | `10,000 × 4` | `2,048 × 3` | `32 × u64` |
| `compact` | `2,048 × 3` | `512 × 3` | `8 × u64` |

## Equivalence Method

For each profile, Racket compiles the existing application-layer fixture into a full Scene. `export_noir_compiler_profile_plan.rkt` independently extracts the semantic subset. Rust invokes:

```text
noir-compiler lower APP_ID PROFILE OUTPUT
```

The two outputs are parsed and validated by `noir-ir diff-profile`. Equality covers stable naming, resident endpoint order, data view capacities and owners, auxiliary action IDs, transaction slot/state/delta bindings, and acknowledged bitset geometry. A negative control changes `word_count: 32` to `31`; the shared validator rejects it before equality can be accepted.

## Verification

```bash
bash tools/verify_noir_compiler_profile_lowering_v1.sh
```

The regression builds and tests `noir-ir` and `noir-compiler`, exports both Racket profiles, compares Rust lowerings, rejects an unsupported profile, rejects an invalid application ID, and rejects tampered word geometry.

Expected marker:

```text
NOIR_COMPILER_PROFILE_LOWERING_V1_REGRESSION: PASS
```

## Boundaries

This pass is not a replacement compiler yet. Racket remains the authoritative producer of the full Scene and all rendering addresses. The Rust pass cannot accept arbitrary capacities, third arenas, free transactions, external data sources, arbitrary row-state domains, dynamic layout, or unbounded identifiers. Its purpose is to establish a validated Rust semantic core before those later frontend passes are migrated.
