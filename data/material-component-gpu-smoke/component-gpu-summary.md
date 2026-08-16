# Noir Real-GPU Component Matrix v1

**Commit:** `958b224f7f117bf52f50ac3227a72e047222c88d`  
**Adapter:** `Microsoft Direct3D12 (AMD RadeonT 780M)` via `Vulkan`  
**Protocol:** 2 sessions; 5 warm-up iterations; 20 samples per replay row.

| Fixture | Compiler-selected workload | Sessions | GPU median of session medians (µs) | GPU P95 of session P95s (µs) | CPU submit median (µs) | Tiles | Glyph draws | Winner writes (bytes) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| dashboard | `coalesced-activate-material-alerts$target` | 2 | 23.56 | 26.79 | 157.01 | 1 | 1 | 24 |
| dashboard | `coalesced-activate-material-overview$target` | 2 | 23.40 | 26.47 | 175.93 | 1 | 1 | 24 |
| dashboard | `coalesced-activate-material-refresh-button` | 2 | 28.52 | 30.02 | 175.72 | 2 | 2 | 36 |
| dashboard | `coalesced-activate-material-systems$target` | 2 | 23.12 | 26.69 | 152.92 | 1 | 1 | 24 |
| overlay | `coalesced-activate-deployment-confirm` | 2 | 27.40 | 28.90 | 171.41 | 2 | 2 | 32 |
| overlay | `coalesced-activate-deployment-dismiss` | 2 | 27.42 | 28.01 | 175.46 | 2 | 2 | 32 |
| overlay | `coalesced-activate-menu-copy$target` | 2 | 40.22 | 41.35 | 175.09 | 2 | 2 | 32 |
| overlay | `coalesced-activate-menu-export$target` | 2 | 40.62 | 41.45 | 171.52 | 2 | 2 | 32 |
| overlay | `coalesced-activate-menu-pin$target` | 2 | 40.48 | 41.55 | 175.72 | 2 | 2 | 32 |

> This report is valid only for the single non-CPU adapter admitted by the runner. It is a Noir component-path measurement, not a cross-framework claim.
