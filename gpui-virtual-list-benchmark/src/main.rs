use gpui::{
    div, prelude::*, px, rgb, size, uniform_list, App, Application, Bounds, Context,
    Window, WindowBounds, WindowOptions,
};

const ROWS: [&str; 8] = [
    "NODE AAA", "NODE BBB", "NODE CCC", "NODE DDD",
    "NODE EEE", "NODE FFF", "NODE GGG", "NODE HHH",
];
const VIEWPORT_ROWS: usize = 3;
const ROW_HEIGHT: f32 = 28.0;

/// Same declared data shape as Noir's virtual-list fixture: fixed capacity 8,
/// 28px rows and an 84px three-row viewport. GPUI renders this through its
/// official `uniform_list` element; the Noir side uses compiler-fixed row slots.
struct VirtualListBenchmark {
    refresh_count: u32,
}

impl Render for VirtualListBenchmark {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex()
            .flex_col()
            .size_full()
            .p(px(24.0))
            .gap(px(12.0))
            .bg(rgb(0x090e18))
            .text_color(rgb(0xd7e6ff))
            .child(div().text_xl().child("NOIR VIRTUAL LIST"))
            // A fixed three-byte counter mirrors Noir's `refresh-count` text-run.
            .child(div().id("refresh-count").child(format!("{:03}", self.refresh_count % 1000)))
            .child(
                uniform_list(
                    "virtual-list-rows",
                    ROWS.len(),
                    cx.processor(|_this, range: std::ops::Range<usize>, _window, _cx| {
                        if std::env::var_os("GPUI_SCROLL_TRACE").is_some() {
                            println!("gpui-visible-range={}..{}", range.start, range.end);
                        }
                        range
                            .map(|index| {
                                div()
                                    .id(index)
                                    .h(px(ROW_HEIGHT))
                                    .flex_none()
                                    .bg(rgb(0x1c2433))
                                    .border_b_1()
                                    .border_color(rgb(0x2b3850))
                                    .child(ROWS[index])
                            })
                            .collect::<Vec<_>>()
                    }),
                )
                .h(px(VIEWPORT_ROWS as f32 * ROW_HEIGHT)),
            )
            .child(
                div()
                    .id("refresh-list-button")
                    .h(px(46.0))
                    .cursor_pointer()
                    .bg(rgb(0x14b878))
                    .on_click(cx.listener(|this, _event, _window, cx| {
                        this.refresh_count = this.refresh_count.wrapping_add(1);
                        println!("gpui-refresh-event count={}", this.refresh_count);
                        cx.notify();
                    }))
                    .child("REFRESH"),
            )
    }
}

fn main() {
    Application::new().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(640.0), px(360.0)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            |_, cx| cx.new(|_| VirtualListBenchmark { refresh_count: 0 }),
        )
        .expect("open GPUI benchmark window");
    });
}
