use anyhow::{bail, Context, Result};
use bytemuck::{Pod, Zeroable};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::mpsc;

const WIDTH: u32 = 640;
const HEIGHT: u32 = 360;
const PIXEL_BYTES: u32 = 4;
const GLYPH_CELL_BYTES: usize = 32;
const ATLAS_GLYPH_WIDTH: u32 = 6;
const ATLAS_GLYPH_HEIGHT: u32 = 8;
const ATLAS_DIGIT_COUNT: u32 = 10;
const ATLAS_WIDTH: u32 = ATLAS_GLYPH_WIDTH * ATLAS_DIGIT_COUNT;
const ATLAS_HEIGHT: u32 = ATLAS_GLYPH_HEIGHT;

#[derive(Debug, Deserialize)]
struct Scene {
    dynamic_node_count: usize,
    resource_budget: ResourceBudget,
    #[serde(default)]
    state: HashMap<String, i64>,
    #[serde(default)]
    actions: HashMap<String, ActionPlan>,
    update_plan: Vec<Vec<Value>>,
    #[serde(default)]
    layout_plan: Vec<LayoutEntry>,
    #[serde(default)]
    event_map: Vec<EventBinding>,
    #[serde(default)]
    animation_tracks: Vec<AnimationTrack>,
    #[serde(default)]
    frame_schedule: Vec<FrameTask>,
    #[serde(default)]
    conflict_graph: Vec<ConflictEdge>,
    #[serde(default)]
    render_schedules: Vec<RenderSchedule>,
}

#[derive(Debug, Deserialize)]
struct ResourceBudget {
    node_capacity: usize,
    instance_capacity: usize,
    glyph_capacity: usize,
}

#[derive(Clone, Debug, Deserialize)]
struct StateWrite {
    state: String,
    op: String,
    value: i64,
}

#[derive(Clone, Debug, Deserialize)]
struct GpuUpdate {
    kind: String,
    node: String,
    state: String,
    offset: usize,
    byte_length: usize,
    glyph_count: usize,
}

#[derive(Clone, Debug, Deserialize)]
struct ActionPlan {
    writes: Vec<StateWrite>,
    #[serde(default)]
    gpu_updates: Vec<GpuUpdate>,
    #[serde(default)]
    instance_updates: Vec<InstanceUpdate>,
    #[serde(default)]
    damage: Vec<DamageRegion>,
}

#[derive(Clone, Debug, Deserialize)]
struct InstanceUpdate {
    kind: String,
    node: String,
    state: String,
    offset: usize,
    byte_length: usize,
    field: String,
    scale: f32,
}

#[derive(Clone, Debug, Deserialize)]
struct DamageRegion {
    kind: String,
    node: String,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    instance_offset: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
struct QuadInstance {
    pos: [f32; 2],
    size: [f32; 2],
    color: [f32; 4],
    glyph_word_offset: u32,
    glyph_enabled: u32,
    glyph_count: u32,
}

impl QuadInstance {
    fn layout<'a>() -> wgpu::VertexBufferLayout<'a> {
        wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<QuadInstance>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Instance,
            attributes: &[
                wgpu::VertexAttribute { offset: 0, shader_location: 0, format: wgpu::VertexFormat::Float32x2 },
                wgpu::VertexAttribute { offset: 8, shader_location: 1, format: wgpu::VertexFormat::Float32x2 },
                wgpu::VertexAttribute { offset: 16, shader_location: 2, format: wgpu::VertexFormat::Float32x4 },
                wgpu::VertexAttribute { offset: 32, shader_location: 3, format: wgpu::VertexFormat::Uint32 },
                wgpu::VertexAttribute { offset: 36, shader_location: 4, format: wgpu::VertexFormat::Uint32 },
                wgpu::VertexAttribute { offset: 40, shader_location: 5, format: wgpu::VertexFormat::Uint32 },
            ],
        }
    }
}

#[derive(Clone, Debug, Deserialize)]
struct EventBinding {
    slot: usize,
    node: String,
    action: String,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    z_index: i32,
    instance_offset: usize,
    base_color: [f32; 4],
    hover_color: [f32; 4],
    pressed_color: [f32; 4],
    base_pos: [f32; 2],
    pressed_pos: [f32; 2],
}

#[derive(Clone, Debug, Deserialize)]
struct WriteRange {
    offset: usize,
    byte_length: usize,
}

#[derive(Clone, Debug, Deserialize)]
struct FrameTask {
    id: String,
    kind: String,
    priority: i32,
    writes: Vec<WriteRange>,
}

#[derive(Clone, Debug, Deserialize)]
struct ConflictEdge {
    left: String,
    right: String,
    winner: String,
    overlaps: Vec<WriteRange>,
}

#[derive(Clone, Debug, Deserialize)]
struct DrawRange {
    first_instance: u32,
    instance_count: u32,
    vertex_count: u32,
    batch_key: String,
    z_layer: f32,
    clip_stack_id: String,
    clip_rect: [f32; 4],
    blend_mode: String,
    opaque: bool,
}

#[derive(Clone, Debug, Deserialize)]
struct ScissorTile {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    nodes: Vec<String>,
    draw_ranges: Vec<DrawRange>,
    fallback_reason: String,
    selected_strategy: String,
    candidate_costs: HashMap<String, f32>,
}

#[derive(Clone, Debug, Deserialize)]
struct RenderSchedule {
    id: String,
    task_ids: Vec<String>,
    tiles: Vec<ScissorTile>,
    coverage: f32,
    full_redraw: bool,
    profile_id: String,
}

#[derive(Clone, Debug, Deserialize)]
struct AnimationTrack {
    id: String,
    node: String,
    instance_offset: usize,
    pos_offset: usize,
    color_offset: usize,
    duration_ms: u32,
    easing: String,
    pos_from: [f32; 2],
    pos_to: [f32; 2],
    color_from: [f32; 4],
    color_to: [f32; 4],
    damage: DamageRegion,
}

#[derive(Clone, Debug, Deserialize)]
struct LayoutEntry {
    id: String,
    tag: String,
    ndc_pos: [f32; 2],
    ndc_size: [f32; 2],
    color: [f32; 4],
    glyph_offset: usize,
    glyph_count: usize,
    instance_offset: usize,
    vertex_count: u32,
}

#[derive(Debug)]
struct UpdateAudit {
    instance_writes_after_initial: Vec<(usize, usize)>,
    glyph_writes_after_initial: Vec<(usize, usize)>,
    damage_regions: Vec<(String, f32, f32, f32, f32)>,
}

fn validate_event_map(scene: &Scene) -> Result<()> {
    let mut expected_slot = 0usize;
    let mut seen_nodes = std::collections::HashSet::new();
    for event in &scene.event_map {
        if event.slot != expected_slot {
            bail!("Event Map slot {} is not stable/contiguous; expected {expected_slot}", event.slot);
        }
        expected_slot += 1;
        if event.width <= 0.0 || event.height <= 0.0 {
            bail!("Event Map entry {} has empty hit rect", event.node);
        }
        if !seen_nodes.insert(&event.node) {
            bail!("Event Map has duplicate node {}", event.node);
        }
        if !scene.actions.contains_key(&event.action) {
            bail!("Event Map entry {} refers to missing action {}", event.node, event.action);
        }
        if event.instance_offset % std::mem::size_of::<QuadInstance>() != 0 {
            bail!("Event Map entry {} has non-aligned instance offset", event.node);
        }
        if !event.base_color.iter().chain(event.hover_color.iter()).chain(event.pressed_color.iter()).all(|v| v.is_finite())
            || !event.base_pos.iter().chain(event.pressed_pos.iter()).all(|v| v.is_finite()) {
            bail!("Event Map entry {} has non-finite interaction style", event.node);
        }
    }
    Ok(())
}

fn validate_animation_tracks(scene: &Scene) -> Result<()> {
    if scene.animation_tracks.len() != scene.event_map.len() {
        bail!("compiler emitted {} animation track(s) for {} event binding(s)", scene.animation_tracks.len(), scene.event_map.len());
    }
    for track in &scene.animation_tracks {
        let event = scene.event_map.iter().find(|event| event.node == track.node)
            .with_context(|| format!("track {} has no Event Map binding", track.id))?;
        if track.instance_offset != event.instance_offset
            || track.pos_offset != event.instance_offset
            || track.color_offset != event.instance_offset + 16 {
            bail!("track {} has invalid fixed instance field offsets", track.id);
        }
        if track.duration_ms != 80 || track.easing != "ease-out" {
            bail!("track {} violates the compiled 80ms ease-out MVP contract", track.id);
        }
        if track.damage.node != track.node || track.damage.instance_offset != track.instance_offset
            || track.damage.width <= 0.0 || track.damage.height <= 0.0 {
            bail!("track {} has invalid Damage Plan", track.id);
        }
        if !track.pos_from.iter().chain(track.pos_to.iter())
            .chain(track.color_from.iter()).chain(track.color_to.iter()).all(|v| v.is_finite()) {
            bail!("track {} has non-finite keyframe values", track.id);
        }
    }
    Ok(())
}

fn ranges_overlap(left: &WriteRange, right: &WriteRange) -> Option<WriteRange> {
    let start = left.offset.max(right.offset);
    let end = (left.offset + left.byte_length).min(right.offset + right.byte_length);
    (start < end).then_some(WriteRange { offset: start, byte_length: end - start })
}

fn validate_frame_schedule(scene: &Scene) -> Result<()> {
    let task_by_id = scene.frame_schedule.iter().map(|task| (task.id.as_str(), task)).collect::<HashMap<_, _>>();
    if task_by_id.len() != scene.frame_schedule.len() || scene.frame_schedule.len() != 12 {
        bail!("expected 12 uniquely compiled scheduler tasks, got {}", scene.frame_schedule.len());
    }
    for task in &scene.frame_schedule {
        if task.writes.is_empty() || !matches!(task.kind.as_str(), "release" | "hover" | "pressed" | "action") {
            bail!("scheduler task {} has invalid kind or empty write set", task.id);
        }
        for range in &task.writes {
            if range.byte_length == 0 { bail!("scheduler task {} contains empty write range", task.id); }
        }
    }
    for edge in &scene.conflict_graph {
        let left = task_by_id.get(edge.left.as_str()).context("conflict left task missing")?;
        let right = task_by_id.get(edge.right.as_str()).context("conflict right task missing")?;
        let winner = task_by_id.get(edge.winner.as_str()).context("conflict winner task missing")?;
        if winner.priority < left.priority || winner.priority < right.priority || edge.overlaps.is_empty() {
            bail!("conflict {} / {} has invalid winner or overlap", edge.left, edge.right);
        }
        let actual = left.writes.iter().flat_map(|l| right.writes.iter().filter_map(move |r| ranges_overlap(l, r))).collect::<Vec<_>>();
        if actual.len() != edge.overlaps.len() || actual.iter().zip(&edge.overlaps).any(|(a, b)| a.offset != b.offset || a.byte_length != b.byte_length) {
            bail!("conflict {} / {} does not match compiler write ranges", edge.left, edge.right);
        }
    }
    let expected = scene.conflict_graph.iter().find(|edge|
        edge.left == "release-advance-progress-button" && edge.right == "hover-advance-progress-button")
        .context("expected release/hover conflict edge is missing")?;
    if expected.winner != "hover-advance-progress-button" || expected.overlaps.len() != 1
        || expected.overlaps[0].offset != 632 || expected.overlaps[0].byte_length != 16 {
        bail!("compiled release/hover conflict priority is wrong");
    }
    Ok(())
}

fn validate_render_schedules(scene: &Scene) -> Result<()> {
    if scene.render_schedules.len() != 1 { bail!("expected one compiled Render Schedule"); }
    let schedule = &scene.render_schedules[0];
    if schedule.id != "concurrent-frame" || schedule.full_redraw || schedule.profile_id.is_empty() || schedule.task_ids != ["advance-progress", "hover-refresh-fps-button", "release-advance-progress-button"] {
        bail!("unexpected Render Schedule identity or task order");
    }
    if schedule.tiles.len() != 3 || !(schedule.coverage > 0.0 && schedule.coverage < 0.60) {
        bail!("Render Schedule should have three local tiles below full redraw threshold");
    }
    let mut area = 0.0f32;
    for tile in &schedule.tiles {
        if tile.width <= 0.0 || tile.height <= 0.0 || tile.x < 0.0 || tile.y < 0.0
            || tile.x + tile.width > WIDTH as f32 || tile.y + tile.height > HEIGHT as f32 || tile.nodes.is_empty() || tile.draw_ranges.is_empty() {
            bail!("invalid scissor tile in Render Schedule");
        }
        let mut previous_end = 0u32;
        for range in &tile.draw_ranges {
            if range.instance_count == 0 || range.vertex_count != 18 || !range.batch_key.starts_with("shared-quad-atlas|clip:")
                || range.first_instance < previous_end || range.first_instance + range.instance_count > scene.resource_budget.instance_capacity as u32
                || !matches!(range.blend_mode.as_str(), "opaque" | "alpha")
                || range.clip_rect[2] <= 0.0 || range.clip_rect[3] <= 0.0 || range.clip_rect[0] < 0.0 || range.clip_rect[1] < 0.0 {
                bail!("invalid or overlapping compiled composite draw range in Render Schedule");
            }
            if (range.blend_mode == "opaque") != range.opaque {
                bail!("compiled blend mode and opaque flag disagree");
            }
            previous_end = range.first_instance + range.instance_count;
        }
        area += tile.width * tile.height;
    }
    if ((area / (WIDTH * HEIGHT) as f32) - schedule.coverage).abs() > 0.0001 {
        bail!("Render Schedule coverage disagrees with tiles");
    }
    let submitted_instances: u32 = schedule.tiles.iter().flat_map(|tile| tile.draw_ranges.iter()).map(|range| range.instance_count).sum();
    let exact = |tile: &ScissorTile, expected: &[(u32, u32)]| {
        tile.draw_ranges.len() == expected.len() && tile.draw_ranges.iter().zip(expected).all(|(actual, expected)|
            actual.first_instance == expected.0 && actual.instance_count == expected.1)
    };
    if schedule.tiles[0].fallback_reason == "cost-model-full-tile-redraw" {
        let first = &schedule.tiles[0];
        let fragment_cost = *first.candidate_costs.get("fragment").context("missing fragment candidate cost")?;
        let complete_cost = *first.candidate_costs.get("complete-lower-range").context("missing complete candidate cost")?;
        let full_cost = *first.candidate_costs.get("full-tile-redraw").context("missing full candidate cost")?;
        if first.selected_strategy != "full-tile-redraw" || !(fragment_cost > full_cost && full_cost < complete_cost)
            || submitted_instances != 10 || !exact(first, &[(5, 1), (6, 1), (7, 1), (8, 1), (9, 1), (10, 1)])
            || !exact(&schedule.tiles[1], &[(11, 2)]) || !exact(&schedule.tiles[2], &[(11, 1), (14, 1)])
            || first.draw_ranges.iter().any(|range| range.clip_stack_id.contains("fragment:"))
            || first.draw_ranges[3..].iter().map(|range| range.z_layer as i32).collect::<Vec<_>>() != vec![10, 11, 12]
            || schedule.tiles[1].selected_strategy != "fragment" || schedule.tiles[2].selected_strategy != "fragment" {
            bail!("cost model did not choose full-tile for dense coverage and fragment for light tiles");
        }
        if submitted_instances >= (scene.resource_budget.instance_capacity * schedule.tiles.len()) as u32 {
            bail!("cost model should remain below full tile draw work");
        }
        return Ok(());
    }
    let overlay = schedule.tiles[0].draw_ranges.last().context("progress tile has no overlay range")?;
    if overlay.z_layer != 10.0 || !overlay.clip_stack_id.starts_with("progress-shell>progress-layer") {
        bail!("compiled nested-clip overlay context is wrong");
    }
    if overlay.blend_mode == "alpha" {
        // 半透明上层不能遮挡消除：outer shell、inner layer、progress 与 alpha overlay 全部保留。
        if submitted_instances != 8 || !exact(&schedule.tiles[0], &[(5, 1), (6, 1), (7, 1), (8, 1)])
            || !exact(&schedule.tiles[1], &[(9, 2)]) || !exact(&schedule.tiles[2], &[(9, 1), (12, 1)])
            || overlay.opaque || overlay.clip_rect != [34.0, 180.0, 572.0, 22.0] {
            bail!("alpha overlay illegally removed lower painter-order ranges");
        }
    } else if overlay.blend_mode == "opaque" && overlay.clip_rect == [34.0, 180.0, 572.0, 22.0] {
        // 完全不透明且完整覆盖时，compiler 应只保留高 z overlay。
        if submitted_instances != 5 || !exact(&schedule.tiles[0], &[(8, 1)])
            || !exact(&schedule.tiles[1], &[(9, 2)]) || !exact(&schedule.tiles[2], &[(9, 1), (12, 1)])
            || !overlay.opaque {
            bail!("opaque overlay did not produce the expected safe occlusion cull");
        }
    } else if overlay.blend_mode == "opaque" && overlay.clip_rect == [34.0, 180.0, 286.0, 22.0] {
        // 部分覆盖：tooltip 占左半区，底层三个 range 仅在右半区保留 fragment。
        let lower = &schedule.tiles[0].draw_ranges[..3];
        if submitted_instances != 8 || !exact(&schedule.tiles[0], &[(5, 1), (6, 1), (7, 1), (8, 1)])
            || !exact(&schedule.tiles[1], &[(9, 2)]) || !exact(&schedule.tiles[2], &[(9, 1), (12, 1)])
            || !overlay.opaque || !lower.iter().all(|range| range.clip_rect == [320.0, 180.0, 286.0, 22.0]
                                                 && range.clip_stack_id.contains("fragment:0")) {
            bail!("partial opaque coverage did not compile into the expected right-side fragments");
        }
    } else {
        bail!("unsupported overlay composite mode/rect: {} {:?}", overlay.blend_mode, overlay.clip_rect);
    }
    if submitted_instances >= (scene.resource_budget.instance_capacity * schedule.tiles.len()) as u32 {
        bail!("Tile Cull did not reduce compiled draw work: {submitted_instances} instances");
    }
    Ok(())
}

fn hit_test<'a>(event_map: &'a [EventBinding], x: f32, y: f32) -> Option<&'a EventBinding> {
    event_map
        .iter()
        .filter(|event| x >= event.x && x < event.x + event.width && y >= event.y && y < event.y + event.height)
        .max_by_key(|event| event.z_index)
}

#[derive(Debug, Clone, Copy)]
enum InteractionPhase { Hover, Pressed }

fn apply_interaction_patch(
    queue: &wgpu::Queue,
    instance_buffer: &wgpu::Buffer,
    event: &EventBinding,
    phase: InteractionPhase,
) -> Result<Vec<(usize, usize)>> {
    const POS_OFFSET: usize = 0;
    const COLOR_OFFSET: usize = 16;
    let mut writes = Vec::new();
    let mut write = |field_offset: usize, bytes: &[u8]| -> Result<()> {
        let offset = event.instance_offset + field_offset;
        // Event binding 和 QuadInstance ABI 均在启动时校验；此处没有 node tree 寻址。
        queue.write_buffer(instance_buffer, offset as u64, bytes);
        writes.push((offset, bytes.len()));
        Ok(())
    };
    match phase {
        InteractionPhase::Hover => {
            write(COLOR_OFFSET, bytemuck::cast_slice(&event.hover_color))?;
        }
        InteractionPhase::Pressed => {
            write(POS_OFFSET, bytemuck::cast_slice(&event.pressed_pos))?;
            write(COLOR_OFFSET, bytemuck::cast_slice(&event.pressed_color))?;
        }
    }
    Ok(writes)
}

fn ease_out(t: f32) -> f32 {
    1.0 - (1.0 - t.clamp(0.0, 1.0)).powi(2)
}

fn lerp<const N: usize>(from: [f32; N], to: [f32; N], t: f32) -> [f32; N] {
    std::array::from_fn(|index| from[index] + (to[index] - from[index]) * t)
}

fn apply_frame_clock_patch_masked(
    queue: &wgpu::Queue,
    instance_buffer: &wgpu::Buffer,
    track: &AnimationTrack,
    elapsed_ms: u32,
    write_pos: bool,
    write_color: bool,
) -> Result<(f32, Vec<(usize, usize)>)> {
    if elapsed_ms > track.duration_ms {
        bail!("frame clock {}ms exceeds compiled track {} duration {}ms", elapsed_ms, track.id, track.duration_ms);
    }
    let t = ease_out(elapsed_ms as f32 / track.duration_ms as f32);
    let pos = lerp(track.pos_from, track.pos_to, t);
    let color = lerp(track.color_from, track.color_to, t);
    let mut writes = Vec::new();
    if write_pos {
        queue.write_buffer(instance_buffer, track.pos_offset as u64, bytemuck::cast_slice(&pos));
        writes.push((track.pos_offset, 8));
    }
    if write_color {
        queue.write_buffer(instance_buffer, track.color_offset as u64, bytemuck::cast_slice(&color));
        writes.push((track.color_offset, 16));
    }
    Ok((t, writes))
}

fn apply_frame_clock_patch(
    queue: &wgpu::Queue,
    instance_buffer: &wgpu::Buffer,
    track: &AnimationTrack,
    elapsed_ms: u32,
) -> Result<(f32, Vec<(usize, usize)>)> {
    apply_frame_clock_patch_masked(queue, instance_buffer, track, elapsed_ms, true, true)
}

fn precompiled_instances(scene: &Scene, bindings: &[GpuUpdate]) -> Result<Vec<QuadInstance>> {
    if scene.layout_plan.len() != scene.resource_budget.instance_capacity {
        bail!("compiler emitted {} layout entries for {} instance slots", scene.layout_plan.len(), scene.resource_budget.instance_capacity);
    }
    let instance_size = std::mem::size_of::<QuadInstance>();
    if instance_size != 44 {
        bail!("unexpected QuadInstance ABI: {instance_size}");
    }
    let binding_by_node = bindings
        .iter()
        .map(|binding| (binding.node.as_str(), binding))
        .collect::<HashMap<_, _>>();
    let mut instances = vec![QuadInstance::zeroed(); scene.resource_budget.instance_capacity];
    let mut occupied = vec![false; scene.resource_budget.instance_capacity];

    for entry in &scene.layout_plan {
        if !matches!(entry.tag.as_str(), "column" | "row" | "stack" | "grid" | "text" | "button" | "progress" | "overlay" | "spacer") {
            bail!("Layout Plan contains unsupported node tag {}", entry.tag);
        }
        if entry.instance_offset % instance_size != 0 {
            bail!("{} has non-aligned instance offset {}", entry.id, entry.instance_offset);
        }
        let slot = entry.instance_offset / instance_size;
        if slot >= instances.len() || occupied[slot] {
            bail!("{} has invalid or duplicate instance slot {slot}", entry.id);
        }
        let expected_vertices = if entry.glyph_count > 0 { (entry.glyph_count * 6) as u32 } else { 6 };
        if entry.vertex_count != expected_vertices {
            bail!("{} has inconsistent draw vertex count", entry.id);
        }
        if entry.glyph_count > 0 {
            let binding = binding_by_node
                .get(entry.id.as_str())
                .with_context(|| format!("layout text-run {} has no action binding", entry.id))?;
            if binding.offset != entry.glyph_offset || binding.glyph_count != entry.glyph_count {
                bail!("layout and action plan disagree for text-run {}", entry.id);
            }
        } else if entry.glyph_offset != 0 {
            bail!("static layout entry {} must have zero glyph offset", entry.id);
        }
        instances[slot] = QuadInstance {
            pos: entry.ndc_pos,
            size: entry.ndc_size,
            color: entry.color,
            glyph_word_offset: (entry.glyph_offset / 4) as u32,
            glyph_enabled: u32::from(entry.glyph_count > 0),
            glyph_count: entry.glyph_count as u32,
        };
        occupied[slot] = true;
    }
    if occupied.iter().any(|used| !used) {
        bail!("compiler Layout Plan left at least one instance slot unassigned");
    }
    Ok(instances)
}

fn all_gpu_updates(scene: &Scene) -> Result<Vec<GpuUpdate>> {
    let mut by_node: HashMap<String, GpuUpdate> = HashMap::new();
    for plan in scene.actions.values() {
        for update in &plan.gpu_updates {
            if update.kind != "text-run" {
                bail!("MVP only supports text-run GPU updates, got {}", update.kind);
            }
            if update.byte_length != update.glyph_count * GLYPH_CELL_BYTES {
                bail!("{} has inconsistent glyph byte length", update.node);
            }
            if update.offset + update.byte_length > scene.resource_budget.glyph_capacity * GLYPH_CELL_BYTES {
                bail!("{} exceeds compiler glyph buffer budget", update.node);
            }
            if let Some(existing) = by_node.insert(update.node.clone(), update.clone()) {
                if existing.offset != update.offset || existing.byte_length != update.byte_length {
                    bail!("node {} has incompatible GPU update ranges", update.node);
                }
            }
        }
    }
    let mut updates: Vec<_> = by_node.into_values().collect();
    updates.sort_by_key(|update| update.offset);
    for pair in updates.windows(2) {
        let left = &pair[0];
        let right = &pair[1];
        if right.offset < left.offset + left.byte_length {
            bail!("overlapping compiler ranges: {} and {}", left.node, right.node);
        }
    }
    let expected_text_runs = scene
        .update_plan
        .iter()
        .filter(|step| step.first().and_then(Value::as_str) == Some("text-run-patch"))
        .count();
    if updates.len() != expected_text_runs {
        bail!(
            "{} text-run patch(es) but {} exact glyph binding(s)",
            expected_text_runs,
            updates.len()
        );
    }
    Ok(updates)
}

fn digit_payload(value: i64, glyph_count: usize) -> Result<Vec<u8>> {
    if value < 0 {
        bail!("negative values are outside the numeric glyph MVP");
    }
    let text = format!("{:0width$}", value, width = glyph_count);
    if text.len() > glyph_count {
        bail!("value {value} exceeds the {glyph_count}-glyph license");
    }
    let mut bytes = vec![0u8; glyph_count * GLYPH_CELL_BYTES];
    for (index, digit) in text.bytes().enumerate() {
        let numeric = (digit - b'0') as u32;
        let base = index * GLYPH_CELL_BYTES;
        bytes[base..base + 4].copy_from_slice(&numeric.to_le_bytes());
    }
    Ok(bytes)
}

fn digit_atlas_pixels() -> Vec<u8> {
    // 每个数字为 3×5 像素，放入有 1 像素 padding 的 6×8 atlas cell。
    // 这是真实纹理 atlas，而不是 fragment shader 的数字/颜色分支。
    let patterns: [[u8; 5]; 10] = [
        [0b111, 0b101, 0b101, 0b101, 0b111], // 0
        [0b010, 0b110, 0b010, 0b010, 0b111], // 1
        [0b111, 0b001, 0b111, 0b100, 0b111], // 2
        [0b111, 0b001, 0b111, 0b001, 0b111], // 3
        [0b101, 0b101, 0b111, 0b001, 0b001], // 4
        [0b111, 0b100, 0b111, 0b001, 0b111], // 5
        [0b111, 0b100, 0b111, 0b101, 0b111], // 6
        [0b111, 0b001, 0b010, 0b010, 0b010], // 7
        [0b111, 0b101, 0b111, 0b101, 0b111], // 8
        [0b111, 0b101, 0b111, 0b001, 0b111], // 9
    ];
    let mut pixels = vec![0u8; (ATLAS_WIDTH * ATLAS_HEIGHT) as usize];
    for (digit, rows) in patterns.iter().enumerate() {
        for (row, bits) in rows.iter().enumerate() {
            for column in 0..3u32 {
                if (bits & (1 << (2 - column))) != 0 {
                    let x = digit as u32 * ATLAS_GLYPH_WIDTH + 1 + column;
                    let y = 1 + row as u32;
                    pixels[(y * ATLAS_WIDTH + x) as usize] = 255;
                }
            }
        }
    }
    pixels
}

fn initial_glyph_bytes(scene: &Scene, bindings: &[GpuUpdate]) -> Result<Vec<u8>> {
    let mut bytes = vec![0u8; scene.resource_budget.glyph_capacity.max(1) * GLYPH_CELL_BYTES];
    for binding in bindings {
        let value = *scene
            .state
            .get(&binding.state)
            .with_context(|| format!("no initial value for state {}", binding.state))?;
        let payload = digit_payload(value, binding.glyph_count)?;
        bytes[binding.offset..binding.offset + binding.byte_length].copy_from_slice(&payload);
    }
    Ok(bytes)
}

fn apply_action(state: &HashMap<String, i64>, action_id: &str, plan: &ActionPlan) -> Result<HashMap<String, i64>> {
    let mut next_state = state.clone();
    for write in &plan.writes {
        let current = next_state
            .get(&write.state)
            .copied()
            .with_context(|| format!("action {action_id} writes unknown state {}", write.state))?;
        let next = match write.op.as_str() {
            "set" => write.value,
            "add" => current + write.value,
            other => bail!("unsupported state operation {other}"),
        };
        next_state.insert(write.state.clone(), next);
    }
    Ok(next_state)
}

fn dispatch_action(
    queue: &wgpu::Queue,
    glyph_buffer: &wgpu::Buffer,
    instance_buffer: &wgpu::Buffer,
    state: &HashMap<String, i64>,
    action_id: &str,
    plan: &ActionPlan,
) -> Result<(HashMap<String, i64>, UpdateAudit)> {
    let next_state = apply_action(state, action_id, plan)?;
    let mut audit = UpdateAudit {
        instance_writes_after_initial: Vec::new(),
        glyph_writes_after_initial: Vec::new(),
        damage_regions: Vec::new(),
    };
    for update in &plan.gpu_updates {
        let value = *next_state
            .get(&update.state)
            .with_context(|| format!("no value after {action_id} for {}", update.state))?;
        let payload = digit_payload(value, update.glyph_count)?;
        if payload.len() != update.byte_length {
            bail!("{} payload did not match compiler byte range", update.node);
        }
        queue.write_buffer(glyph_buffer, update.offset as u64, &payload);
        audit.glyph_writes_after_initial.push((update.offset, payload.len()));
    }

    if plan.instance_updates.len() != plan.damage.len() {
        bail!("{action_id} instance updates and Damage Plan have different lengths");
    }
    for update in &plan.instance_updates {
        if update.kind != "instance-patch" || update.field != "size.x" || update.byte_length != 4 {
            bail!("{action_id} contains an unsupported instance patch for {}", update.node);
        }
        let value = *next_state
            .get(&update.state)
            .with_context(|| format!("no value after {action_id} for {}", update.state))?;
        if value < 0 {
            bail!("{action_id} produced a negative progress value for {}", update.node);
        }
        let payload = (value as f32 * update.scale).to_le_bytes();
        // 唯一的 geometry mutation：编译器给出的 QuadInstance slot + size.x byte offset。
        queue.write_buffer(instance_buffer, update.offset as u64, &payload);
        audit.instance_writes_after_initial.push((update.offset, payload.len()));

        let damage = plan.damage.iter().find(|region| region.node == update.node)
            .with_context(|| format!("{action_id} has no Damage Plan for {}", update.node))?;
        if damage.kind != "rect" || damage.width <= 0.0 || damage.height <= 0.0 {
            bail!("{action_id} has invalid Damage Plan for {}", update.node);
        }
        let expected_instance_offset = update.offset.checked_sub(8)
            .context("instance patch underflow")?;
        if damage.instance_offset != expected_instance_offset {
            bail!("{action_id} Damage Plan does not refer to the patched instance slot");
        }
        audit.damage_regions.push((damage.node.clone(), damage.x, damage.y, damage.width, damage.height));
    }
    Ok((next_state, audit))
}

fn ppm_write(path: &Path, width: u32, height: u32, padded: &[u8], padded_bpr: usize) -> Result<(u64, usize)>{
    let mut out = format!("P6\n{} {}\n255\n", width, height).into_bytes();
    let mut checksum = 0u64;
    let mut non_background = 0usize;
    for y in 0..height as usize {
        let row = &padded[y * padded_bpr..y * padded_bpr + (width * PIXEL_BYTES) as usize];
        for px in row.chunks_exact(4) {
            out.extend_from_slice(&[px[0], px[1], px[2]]);
            checksum = checksum.wrapping_add(px[0] as u64 + px[1] as u64 + px[2] as u64);
            if px[0] > 20 || px[1] > 25 || px[2] > 35 {
                non_background += 1;
            }
        }
    }
    fs::write(path, out).with_context(|| format!("write {}", path.display()))?;
    Ok((checksum, non_background))
}

fn main() -> Result<()> {
    let scene_path = std::env::args().nth(1).unwrap_or_else(|| "../out/counter.scene.json".into());
    let prefix = std::env::args().nth(2).unwrap_or_else(|| "out/noir-counter".into());
    let scene_text = fs::read_to_string(&scene_path).with_context(|| format!("read Scene JSON {scene_path}"))?;
    let scene: Scene = serde_json::from_str(&scene_text).context("parse Noir Scene JSON")?;
    validate_event_map(&scene)?;
    validate_animation_tracks(&scene)?;
    validate_frame_schedule(&scene)?;
    validate_render_schedules(&scene)?;
    let summary_glyph_steps = scene
        .update_plan
        .iter()
        .filter(|step| step.first().and_then(Value::as_str) == Some("text-run-patch"))
        .count();
    let summary_instance_steps = scene
        .update_plan
        .iter()
        .filter(|step| step.first().and_then(Value::as_str) == Some("instance-patch"))
        .count();
    if summary_glyph_steps + summary_instance_steps != scene.dynamic_node_count {
        bail!("global update summary disagrees with dynamic node count");
    }
    let bindings = all_gpu_updates(&scene)?;
    // 无 Scene tree traversal、无 runtime rect/NDC 计算：实例完全由 Racket
    // 宏生成的 layout_plan 和固定 instance_offset 解码而来。
    let instances = precompiled_instances(&scene, &bindings)?;

    println!("Noir Glyph Atlas → wgpu text-run isolation verification");
    println!("  scene nodes     : {}", scene.resource_budget.node_capacity);
    println!("  instance budget : {} (used {})", scene.resource_budget.instance_capacity, instances.len());
    println!("  text-run glyph budget: {}", scene.resource_budget.glyph_capacity);
    println!("  global text-run steps : {summary_glyph_steps}");
    println!("  global instance steps : {summary_instance_steps}");
    println!("  exact bindings  : {:?}", bindings.iter().map(|u| (&u.node, u.offset, u.byte_length)).collect::<Vec<_>>());
    println!("  compiler layout entries: {}", scene.layout_plan.len());
    println!("  host layout solver calls: 0");
    println!("  compiler event bindings: {}", scene.event_map.len());
    println!("  compiler animation tracks: {}", scene.animation_tracks.len());
    println!("  compiler scheduler tasks/conflicts: {}/{}", scene.frame_schedule.len(), scene.conflict_graph.len());
    let tile_instances: u32 = scene.render_schedules[0].tiles.iter().flat_map(|tile| tile.draw_ranges.iter()).map(|range| range.instance_count).sum();
    println!("  compiler render tiles/coverage: {}/{:.4} profile={}", scene.render_schedules[0].tiles.len(), scene.render_schedules[0].coverage, scene.render_schedules[0].profile_id);
    println!("  compiler tile draw instances: {} (full tile draws would submit {})", tile_instances, scene.resource_budget.instance_capacity * scene.render_schedules[0].tiles.len());

    pollster::block_on(render_incremental(scene, bindings, instances, Path::new(&prefix)))
}

async fn render_incremental(
    scene: Scene,
    bindings: Vec<GpuUpdate>,
    instances: Vec<QuadInstance>,
    prefix: &Path,
) -> Result<()> {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::VULKAN,
        dx12_shader_compiler: Default::default(),
        flags: wgpu::InstanceFlags::default(),
        gles_minor_version: wgpu::Gles3MinorVersion::Automatic,
    });
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::LowPower,
            compatible_surface: None,
            force_fallback_adapter: false,
        })
        .await
        .context("no Vulkan adapter available")?;
    let info = adapter.get_info();
    println!("  adapter         : {} ({:?}, {:?})", info.name, info.backend, info.device_type);

    let (device, queue) = adapter
        .request_device(
            &wgpu::DeviceDescriptor {
                label: Some("noir-counter-wgpu-device"),
                required_features: wgpu::Features::empty(),
                required_limits: wgpu::Limits::downlevel_defaults(),
            },
            None,
        )
        .await
        .context("request wgpu device")?;

    let instance_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("noir-ui-instance-buffer"),
        size: (scene.resource_budget.instance_capacity.max(1) * std::mem::size_of::<QuadInstance>()) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    queue.write_buffer(&instance_buffer, 0, bytemuck::cast_slice(&instances));

    // Scissor 局部重绘必须先擦除该 tile 中上一帧残留的几何；此 quad 与主 Scene
    // 使用完全相同的 pipeline/ABI，只是固定为全 NDC 背景颜色并由 scissor 限制范围。
    let scissor_clear_instance = QuadInstance {
        pos: [-1.0, -1.0], size: [2.0, 2.0], color: [0.008, 0.012, 0.025, 1.0],
        glyph_word_offset: 0, glyph_enabled: 0, glyph_count: 0,
    };
    let scissor_clear_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("noir-scissor-clear-instance"),
        size: std::mem::size_of::<QuadInstance>() as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    queue.write_buffer(&scissor_clear_buffer, 0, bytemuck::bytes_of(&scissor_clear_instance));

    let initial_glyphs = initial_glyph_bytes(&scene, &bindings)?;
    let glyph_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("noir-glyph-instance-buffer"),
        size: initial_glyphs.len() as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    queue.write_buffer(&glyph_buffer, 0, &initial_glyphs);

    let atlas_texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("noir-digit-glyph-atlas"),
        size: wgpu::Extent3d { width: ATLAS_WIDTH, height: ATLAS_HEIGHT, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::R8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    let atlas_pixels = digit_atlas_pixels();
    queue.write_texture(
        wgpu::ImageCopyTexture {
            texture: &atlas_texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        &atlas_pixels,
        wgpu::ImageDataLayout { offset: 0, bytes_per_row: Some(ATLAS_WIDTH), rows_per_image: Some(ATLAS_HEIGHT) },
        wgpu::Extent3d { width: ATLAS_WIDTH, height: ATLAS_HEIGHT, depth_or_array_layers: 1 },
    );
    let atlas_view = atlas_texture.create_view(&wgpu::TextureViewDescriptor::default());
    let atlas_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
        label: Some("noir-digit-atlas-nearest-sampler"),
        address_mode_u: wgpu::AddressMode::ClampToEdge,
        address_mode_v: wgpu::AddressMode::ClampToEdge,
        address_mode_w: wgpu::AddressMode::ClampToEdge,
        mag_filter: wgpu::FilterMode::Nearest,
        min_filter: wgpu::FilterMode::Nearest,
        mipmap_filter: wgpu::FilterMode::Nearest,
        ..Default::default()
    });

    let glyph_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("noir-glyph-buffer-layout"),
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0,
            visibility: wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Storage { read_only: true },
                has_dynamic_offset: false,
                min_binding_size: None,
            },
            count: None,
        },
        wgpu::BindGroupLayoutEntry {
            binding: 1,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Texture {
                multisampled: false,
                view_dimension: wgpu::TextureViewDimension::D2,
                sample_type: wgpu::TextureSampleType::Float { filterable: true },
            },
            count: None,
        },
        wgpu::BindGroupLayoutEntry {
            binding: 2,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
            count: None,
        }],
    });
    let glyph_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("noir-text-run-atlas-bind-group"),
        layout: &glyph_layout,
        entries: &[
            wgpu::BindGroupEntry { binding: 0, resource: glyph_buffer.as_entire_binding() },
            wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&atlas_view) },
            wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::Sampler(&atlas_sampler) },
        ],
    });

    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("noir-offscreen-target"),
        size: wgpu::Extent3d { width: WIDTH, height: HEIGHT, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let target_view = target.create_view(&wgpu::TextureViewDescriptor::default());
    let unpadded_bpr = WIDTH * PIXEL_BYTES;
    let alignment = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
    let padded_bpr = ((unpadded_bpr + alignment - 1) / alignment) * alignment;
    let staging = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("noir-readback-buffer"),
        size: (padded_bpr * HEIGHT) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("noir-shared-quad-wgsl"),
        source: wgpu::ShaderSource::Wgsl(include_str!("quad.wgsl").into()),
    });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("noir-shared-quad-layout"),
        bind_group_layouts: &[&glyph_layout],
        push_constant_ranges: &[],
    });
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("noir-shared-quad-pipeline"),
        layout: Some(&pipeline_layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: "vs_main",
            buffers: &[QuadInstance::layout()],
            compilation_options: Default::default(),
        },
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: "fs_main",
            targets: &[Some(wgpu::ColorTargetState {
                format: wgpu::TextureFormat::Rgba8Unorm,
                blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                write_mask: wgpu::ColorWrites::ALL,
            })],
            compilation_options: Default::default(),
        }),
        multiview: None,
    });

    let baseline_path = PathBuf::from(format!("{}-baseline.ppm", prefix.display()));
    let mut previous_frame = render_and_readback(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, instances.len() as u32,
        &target, &target_view, &staging, padded_bpr, &baseline_path,
    )?;
    let mut current_state = scene.state.clone();

    // 不再手写调用 action 名称。每一项都是窗口坐标系中的合成 pointer-down，
    // 先通过 compiler Event Map hit-test，再从命中绑定中取得 action id。
    if hit_test(&scene.event_map, 620.0, 340.0).is_some() {
        bail!("outside pointer unexpectedly hit an Event Map binding");
    }
    for ((pointer_x, pointer_y), expected_action, expected_glyph_writes, expected_instance_writes, expected_damage_node) in [
        ((100.0f32, 250.0f32), "refresh-fps", vec![(0usize, 96usize)], vec![], None::<&str>),
        ((280.0f32, 250.0f32), "refresh-latency", vec![(96usize, 96usize)], vec![], None::<&str>),
    ] {
        let hit = hit_test(&scene.event_map, pointer_x, pointer_y)
            .with_context(|| format!("pointer ({pointer_x}, {pointer_y}) did not hit a compiled button"))?;
        let action_id = hit.action.as_str();
        if action_id != expected_action {
            bail!("pointer ({pointer_x}, {pointer_y}) hit {} → {}, expected {expected_action}", hit.node, action_id);
        }
        let action = scene
            .actions
            .get(action_id)
            .with_context(|| format!("Event Map action {action_id} has no action plan"))?;
        let state_before = current_state.clone();
        let (next_state, audit) = dispatch_action(
            &queue, &glyph_buffer, &instance_buffer, &current_state, action_id, action,
        )?;

        if audit.glyph_writes_after_initial != expected_glyph_writes {
            bail!("{action_id} glyph writes {:?}, expected {:?}", audit.glyph_writes_after_initial, expected_glyph_writes);
        }
        if audit.instance_writes_after_initial != expected_instance_writes {
            bail!("{action_id} instance writes {:?}, expected {:?}", audit.instance_writes_after_initial, expected_instance_writes);
        }
        match expected_damage_node {
            Some(node) => {
                if audit.damage_regions.len() != 1 || audit.damage_regions[0].0 != node {
                    bail!("{action_id} did not emit the expected Damage Plan: {:?}", audit.damage_regions);
                }
            }
            None if !audit.damage_regions.is_empty() => bail!("{action_id} unexpectedly emitted Damage Plan"),
            None => {}
        }
        for (state_id, value) in &state_before {
            let is_written = action.writes.iter().any(|write| write.state == *state_id);
            if !is_written && next_state.get(state_id) != Some(value) {
                bail!("{action_id} changed unrelated state {state_id}");
            }
        }

        let frame_path = PathBuf::from(format!("{}-{}.ppm", prefix.display(), action_id));
        let next_frame = render_and_readback(
            &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, instances.len() as u32,
            &target, &target_view, &staging, padded_bpr, &frame_path,
        )?;
        if previous_frame.0 == next_frame.0 {
            bail!("{action_id} did not produce a visible frame change");
        }
        if next_frame.1 < 1_000 {
            bail!("{action_id} produced an apparently empty frame: {next_frame:?}");
        }

        println!("  pointer         : ({pointer_x}, {pointer_y})");
        println!("  hit             : slot {} / {} → {action_id}", hit.slot, hit.node);
        println!("  action {action_id}");
        println!("    writes          : {:?}", action.writes.iter().map(|w| (&w.state, &w.op, w.value)).collect::<Vec<_>>());
        println!("    glyph writes    : {:?}", audit.glyph_writes_after_initial);
        println!("    instance writes : {:?}", audit.instance_writes_after_initial);
        println!("    damage          : {:?}", audit.damage_regions);
        println!("    checksum        : {} → {}", previous_frame.0, next_frame.0);
        println!("    state           : {:?}", next_state);
        println!("    image           : {}", frame_path.display());
        current_state = next_state;
        previous_frame = next_frame;
    }

    // 第三个按钮演示完整的瞬态交互链：hover 只改 color；pressed 改 pos+color；
    // pointer-up 先恢复 base style，然后才从同一 Event Map binding 分发业务 action。
    let third = hit_test(&scene.event_map, 500.0, 250.0)
        .context("pointer (500, 250) did not hit advance-progress button")?;
    if third.slot != 2 || third.node != "advance-progress-button" || third.action != "advance-progress" {
        bail!("unexpected third Event Map binding: slot {} / {} → {}", third.slot, third.node, third.action);
    }
    let hover_writes = apply_interaction_patch(&queue, &instance_buffer, third, InteractionPhase::Hover)?;
    if hover_writes != vec![(632, 16)] {
        bail!("hover writes {:?}, expected only color field [(632, 16)]", hover_writes);
    }
    let hover_path = PathBuf::from(format!("{}-hover.ppm", prefix.display()));
    let hover_frame = render_and_readback(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, instances.len() as u32,
        &target, &target_view, &staging, padded_bpr, &hover_path,
    )?;
    if hover_frame.0 == previous_frame.0 { bail!("hover did not visibly modify only the target button"); }

    let pressed_writes = apply_interaction_patch(&queue, &instance_buffer, third, InteractionPhase::Pressed)?;
    if pressed_writes != vec![(616, 8), (632, 16)] {
        bail!("pressed writes {:?}, expected position+color fields", pressed_writes);
    }
    let pressed_path = PathBuf::from(format!("{}-pressed.ppm", prefix.display()));
    let pressed_frame = render_and_readback(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, instances.len() as u32,
        &target, &target_view, &staging, padded_bpr, &pressed_path,
    )?;
    if pressed_frame.0 == hover_frame.0 { bail!("pressed did not visibly modify target button"); }

    let track = scene.animation_tracks.iter().find(|track| track.node == third.node)
        .context("pressed button has no compiled release Animation Track")?;
    if track.id != "release-advance-progress-button" || track.damage.instance_offset != 616 {
        bail!("unexpected compiled track {} for {}", track.id, third.node);
    }
    let task = |id: &str| -> Result<&FrameTask> {
        scene.frame_schedule.iter().find(|task| task.id == id)
            .with_context(|| format!("compiled scheduler task {id} is missing"))
    };
    let release_task = task("release-advance-progress-button")?;
    let hover_task = task("hover-refresh-fps-button")?;
    let action_task = task("advance-progress")?;
    let exact = |task: &FrameTask, expected: &[(usize, usize)]| {
        task.writes.len() == expected.len()
            && task.writes.iter().zip(expected).all(|(actual, expected)|
                actual.offset == expected.0 && actual.byte_length == expected.1)
    };
    if !exact(release_task, &[(616, 8), (632, 16)])
        || !exact(hover_task, &[(544, 16)])
        || !exact(action_task, &[(316, 4)]) {
        bail!("compiled concurrent task write sets do not match the fixed ABI");
    }

    // 0ms keyframe establishes the pressed state. At 40ms, scheduler priority is
    // action(40) > hover(20) > release(10), but all three write sets are disjoint.
    let (t0, release0_writes) = apply_frame_clock_patch(&queue, &instance_buffer, track, 0)?;
    if (t0 - 0.0).abs() > 0.0001 || release0_writes != vec![(616, 8), (632, 16)] {
        bail!("0ms release track patch is invalid");
    }
    let release0_path = PathBuf::from(format!("{}-release-000ms.ppm", prefix.display()));
    let release0_frame = render_and_readback(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, instances.len() as u32,
        &target, &target_view, &staging, padded_bpr, &release0_path,
    )?;
    if release0_frame.0 != pressed_frame.0 { bail!("0ms keyframe did not preserve pressed state"); }

    let first = hit_test(&scene.event_map, 100.0, 250.0)
        .context("concurrent hover pointer did not hit first button")?;
    if first.slot != 0 || first.node != "refresh-fps-button" { bail!("unexpected concurrent hover binding"); }
    let action_id = third.action.as_str();
    let action = scene.actions.get(action_id).context("Event Map action is missing")?;
    let (_next_state, action_audit) = dispatch_action(
        &queue, &glyph_buffer, &instance_buffer, &current_state, action_id, action,
    )?;
    let concurrent_hover_writes = apply_interaction_patch(&queue, &instance_buffer, first, InteractionPhase::Hover)?;
    // 本帧激活的是“另一按钮”的 hover，因此与第三按钮 release 没有重叠；
    // release 的 pos/color 两个字段均可写入。冲突 winner 在下面的独立同节点场景验证。
    let (t40, release40_writes) = apply_frame_clock_patch(&queue, &instance_buffer, track, 40)?;
    let concurrent_writes = vec![(316usize, 4usize), (544usize, 16usize), (616usize, 8usize), (632usize, 16usize)];
    let observed_writes = [
        action_audit.instance_writes_after_initial.as_slice(),
        concurrent_hover_writes.as_slice(),
        release40_writes.as_slice(),
    ].concat();
    if observed_writes != concurrent_writes || (t40 - 0.75).abs() > 0.0001 || !action_audit.glyph_writes_after_initial.is_empty() {
        bail!("same-frame scheduler did not enforce the compiled disjoint write sets: {observed_writes:?}");
    }
    let render_schedule = &scene.render_schedules[0];
    let concurrent_path = PathBuf::from(format!("{}-concurrent-040ms.ppm", prefix.display()));
    let concurrent_frame = render_and_readback_scissored(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, &scissor_clear_buffer,
        &target, &target_view, &staging, padded_bpr, &render_schedule.tiles, &concurrent_path,
    )?;
    // Oracle 全屏重绘只用于验证；实际 concurrent frame 已经通过 3 个预编译 scissor tile 完成。
    let oracle_path = PathBuf::from(format!("{}-concurrent-oracle-full.ppm", prefix.display()));
    let oracle_frame = render_and_readback(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, instances.len() as u32,
        &target, &target_view, &staging, padded_bpr, &oracle_path,
    )?;
    if concurrent_frame != oracle_frame {
        bail!("scissor tile render diverged from full-frame oracle: {:?} vs {:?}", concurrent_frame, oracle_frame);
    }

    // 独立冲突场景：同一第三按钮的 hover 与 release 同帧活跃。Conflict Graph
    // 决定 hover 拥有 color [500,516)，故 release 只保留不冲突 pos [484,492)。
    let third_hover_writes = apply_interaction_patch(&queue, &instance_buffer, third, InteractionPhase::Hover)?;
    let (_conflict_t, masked_release_writes) = apply_frame_clock_patch_masked(&queue, &instance_buffer, track, 40, true, false)?;
    if third_hover_writes != vec![(632, 16)] || masked_release_writes != vec![(616, 8)] {
        bail!("compiled conflict winner did not isolate third hover/release fields");
    }
    let third_tile = render_schedule.tiles.iter().find(|tile| tile.nodes.iter().any(|node| node == "advance-progress-button"))
        .context("compiled render schedule lacks third button tile")?;
    let conflict_path = PathBuf::from(format!("{}-conflict-040ms.ppm", prefix.display()));
    let conflict_frame = render_and_readback_scissored(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, &scissor_clear_buffer,
        &target, &target_view, &staging, padded_bpr, std::slice::from_ref(third_tile), &conflict_path,
    )?;
    let conflict_oracle_path = PathBuf::from(format!("{}-conflict-oracle-full.ppm", prefix.display()));
    let conflict_oracle = render_and_readback(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, instances.len() as u32,
        &target, &target_view, &staging, padded_bpr, &conflict_oracle_path,
    )?;
    if conflict_frame != conflict_oracle { bail!("conflict scissor render diverged from full oracle"); }

    let (t80, release80_writes) = apply_frame_clock_patch(&queue, &instance_buffer, track, 80)?;
    if release80_writes != vec![(616, 8), (632, 16)] || (t80 - 1.0).abs() > 0.0001 {
        bail!("80ms release track patch is invalid");
    }
    let release80_path = PathBuf::from(format!("{}-release-080ms.ppm", prefix.display()));
    let release80_frame = render_and_readback(
        &device, &queue, &pipeline, &glyph_bind_group, &instance_buffer, instances.len() as u32,
        &target, &target_view, &staging, padded_bpr, &release80_path,
    )?;
    if concurrent_frame.0 == release0_frame.0 || release80_frame.0 == concurrent_frame.0 {
        bail!("concurrent frame or track endpoint did not visibly change");
    }
    println!("  pointer         : (500, 250) + concurrent hover (100, 250)");
    println!("  scheduler order : advance-progress > hover-refresh-fps-button > release-advance-progress-button");
    println!("  concurrent writes: {:?}", concurrent_writes);
    println!("  scissor tiles/coverage: {}/{:.4}", render_schedule.tiles.len(), render_schedule.coverage);
    println!("  concurrent frame: no cross-node conflict; release writes pos+color");
    println!("  same-node conflict winner: hover-advance-progress-button; release color [632,16] suppressed, writes {:?}+{:?}", third_hover_writes, masked_release_writes);
    println!("  animation track : {} ({}ms {})", track.id, track.duration_ms, track.easing);
    println!("  frame patches   : 0ms/40ms/80ms release [(616, 8), (632, 16)]");
    println!("  action damage   : {:?}", action_audit.damage_regions);
    println!("  concurrent images: {}, {}, {}; oracle {}", release0_path.display(), concurrent_path.display(), release80_path.display(), oracle_path.display());
    println!("  conflict images  : {}; oracle {}", conflict_path.display(), conflict_oracle_path.display());

    println!("  shared pipelines : 1");
    println!("  baseline image   : {}", baseline_path.display());
    Ok(())
}

fn render_and_readback(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pipeline: &wgpu::RenderPipeline,
    glyph_bind_group: &wgpu::BindGroup,
    instance_buffer: &wgpu::Buffer,
    instance_count: u32,
    target: &wgpu::Texture,
    target_view: &wgpu::TextureView,
    staging: &wgpu::Buffer,
    padded_bpr: u32,
    output: &Path,
) -> Result<(u64, usize)> {
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("noir-counter-encoder") });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("noir-counter-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: target_view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color { r: 0.008, g: 0.012, b: 0.025, a: 1.0 }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });
        pass.set_pipeline(pipeline);
        pass.set_bind_group(0, glyph_bind_group, &[]);
        pass.set_vertex_buffer(0, instance_buffer.slice(..));
        // 每个动态 text-run 最多有 3 个 glyph quad（18 vertices）；静态节点的
        // shader 分支仅接受前 6 个 vertex，仍由同一条 pipeline 处理。
        pass.draw(0..18, 0..instance_count);
    }
    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture: target,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: staging,
            layout: wgpu::ImageDataLayout { offset: 0, bytes_per_row: Some(padded_bpr), rows_per_image: Some(HEIGHT) },
        },
        wgpu::Extent3d { width: WIDTH, height: HEIGHT, depth_or_array_layers: 1 },
    );
    queue.submit(Some(encoder.finish()));

    let slice = staging.slice(..);
    let (sender, receiver) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| sender.send(result).expect("readback receiver"));
    device.poll(wgpu::Maintain::Wait);
    receiver.recv().context("wait for readback")??;
    let data = slice.get_mapped_range().to_vec();
    staging.unmap();
    ppm_write(output, WIDTH, HEIGHT, &data, padded_bpr as usize)
}


fn scissor_intersection(tile: &ScissorTile, clip: [f32; 4]) -> Option<(u32, u32, u32, u32)> {
    // 对分数 pixel rect 采取保守外扩：左/上 floor，右/下 ceil。这样 Tile Cull
    // 不会漏掉全量 rasterizer 在边缘产生的覆盖样本。
    let left = tile.x.max(clip[0]).floor().max(0.0) as u32;
    let top = tile.y.max(clip[1]).floor().max(0.0) as u32;
    let right = (tile.x + tile.width).min(clip[0] + clip[2]).ceil().min(WIDTH as f32) as u32;
    let bottom = (tile.y + tile.height).min(clip[1] + clip[3]).ceil().min(HEIGHT as f32) as u32;
    (right > left && bottom > top).then_some((left, top, right - left, bottom - top))
}

fn render_and_readback_scissored(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pipeline: &wgpu::RenderPipeline,
    glyph_bind_group: &wgpu::BindGroup,
    instance_buffer: &wgpu::Buffer,
    scissor_clear_buffer: &wgpu::Buffer,
    target: &wgpu::Texture,
    target_view: &wgpu::TextureView,
    staging: &wgpu::Buffer,
    padded_bpr: u32,
    tiles: &[ScissorTile],
    output: &Path,
) -> Result<(u64, usize)> {
    if tiles.is_empty() { bail!("scissor renderer received no tiles"); }
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("noir-scissor-encoder") });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("noir-scissor-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: target_view,
                resolve_target: None,
                ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });
        pass.set_pipeline(pipeline);
        pass.set_bind_group(0, glyph_bind_group, &[]);
        for tile in tiles {
            let x = tile.x.round() as u32;
            let y = tile.y.round() as u32;
            let width = tile.width.round() as u32;
            let height = tile.height.round() as u32;
            pass.set_scissor_rect(x, y, width, height);
            // 同一 shader/ABI 的背景 quad 清除 tile，再重绘预编译 scene。
            pass.set_vertex_buffer(0, scissor_clear_buffer.slice(..));
            pass.draw(0..6, 0..1);
            pass.set_vertex_buffer(0, instance_buffer.slice(..));
            // macro 已按 (z-layer, stable slot) 排序范围；每条 range 还带独立 clip stack。
            for range in &tile.draw_ranges {
                if let Some((x, y, width, height)) = scissor_intersection(tile, range.clip_rect) {
                    pass.set_scissor_rect(x, y, width, height);
                    pass.draw(0..range.vertex_count, range.first_instance..(range.first_instance + range.instance_count));
                }
            }
        }
    }
    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture { texture: target, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
        wgpu::ImageCopyBuffer {
            buffer: staging,
            layout: wgpu::ImageDataLayout { offset: 0, bytes_per_row: Some(padded_bpr), rows_per_image: Some(HEIGHT) },
        },
        wgpu::Extent3d { width: WIDTH, height: HEIGHT, depth_or_array_layers: 1 },
    );
    queue.submit(Some(encoder.finish()));
    let slice = staging.slice(..);
    let (sender, receiver) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| sender.send(result).expect("readback receiver"));
    device.poll(wgpu::Maintain::Wait);
    receiver.recv().context("wait for scissor readback")??;
    let data = slice.get_mapped_range().to_vec();
    staging.unmap();
    ppm_write(output, WIDTH, HEIGHT, &data, padded_bpr as usize)
}
