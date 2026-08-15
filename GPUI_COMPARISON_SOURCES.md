# GPUI Comparison Sources

- GPUI official site: https://gpui.rs/ — identifies GPUI as Rust UI framework from Zed creators and links official examples/documentation.
- GPUI README: https://github.com/zed-industries/zed/blob/main/crates/gpui/README.md — describes GPUI as hybrid immediate/retained GPU-accelerated Rust UI. Root views are rendered each frame into an element tree; lower-level elements allow efficient large-list/custom-editor implementations. Linux can use X11/Wayland platform features.
- GPUI Render API: https://docs.rs/gpui/latest/gpui/trait.Render.html — Render views return element trees.
- Zed rendering article: https://zed.dev/blog/videogame — documents primitive-specific rendering for rectangles/shadows/text/icons/images, GPU instancing and glyph atlas caching; states 120 FPS as design goal, not a cross-framework benchmark.
- Zed Metal optimization article: https://zed.dev/blog/120fps — documents real M1/M2 macOS 120 FPS investigation, triple buffered instance buffers, frame presentation synchronization and repeated frames during active input.
- Zed Linux architecture article: https://zed.dev/blog/zed-decoded-linux-when — documents GPUI Scene construction from primitives and Linux X11/Wayland rendering through Blade/Vulkan as of May 2024.

No official source retrieved in this task provides a standardized published GPUI-vs-Noir benchmark or a universal microsecond/fps figure applicable across hardware and workloads.

Noir local benchmark source: FUSION_PERFORMANCE_QUANTIFICATION_REPORT.md — 15 independent X11/Vulkan llvmpipe samples of a fixed 3-request versus 1-request fusion microbenchmark; not a framework-level comparison with GPUI or hardware-GPU result.
