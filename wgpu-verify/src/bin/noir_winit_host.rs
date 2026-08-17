use anyhow::{Context, Result};
use bytemuck::{Pod, Zeroable};
use serde::{Deserialize, Deserializer, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{mpsc, Arc};
use std::time::Instant;
use wgpu::util::DeviceExt;
use winit::{
    dpi::PhysicalSize,
    event::{ElementState, Event, MouseButton, WindowEvent},
    keyboard::{Key, ModifiersState, NamedKey},
    event_loop::{ControlFlow, EventLoopBuilder},
    platform::x11::EventLoopBuilderExtX11,
    window::{Window, WindowBuilder},
};

const WIDTH: u32 = 640;
const HEIGHT: u32 = 360;
const GLYPH_CELL_BYTES: usize = 32;
const ATLAS_GLYPH_WIDTH: u32 = 6;
const ATLAS_GLYPH_HEIGHT: u32 = 8;
const ATLAS_GLYPH_COUNT: u32 = 27;
const ATLAS_WIDTH: u32 = ATLAS_GLYPH_WIDTH * ATLAS_GLYPH_COUNT;
const ATLAS_HEIGHT: u32 = ATLAS_GLYPH_HEIGHT;
const ATLAS_PAGES: u32 = 2;
const GLYPH_PLACEMENT_BYTES: usize = 48;
const STATIC_GLYPH_WORD_OFFSET: u32 = u32::MAX;
const VIRTUAL_LIST_PLAN_ABI_SCHEMA: &str = "noir-virtual-list-plan-v1";
const VIRTUAL_LIST_PLAN_ABI_REVISION: u32 = 1;
const ROW_ACTIVATION_PLAN_ABI_SCHEMA: &str = "noir-row-activation-plan-v1";
const ROW_ACTIVATION_PLAN_ABI_REVISION: u32 = 1;
const SCROLLBAR_PLAN_ABI_SCHEMA: &str = "noir-scrollbar-plan-v1";
const SCROLLBAR_PLAN_ABI_REVISION: u32 = 1;
const LIST_NAVIGATION_PLAN_ABI_SCHEMA: &str = "noir-list-navigation-plan-v1";
const LIST_NAVIGATION_PLAN_ABI_REVISION: u32 = 1;
const LOG_BROWSER_PLAN_ABI_SCHEMA: &str = "noir-log-browser-plan-v1";
const LOG_BROWSER_PLAN_ABI_REVISION: u32 = 1;
const FONT_ASSET_PLAN_ABI_SCHEMA: &str = "noir-font-asset-plan-v1";
const FONT_ASSET_PLAN_ABI_REVISION: u32 = 1;
const FONT_PLACEMENT_PLAN_ABI_SCHEMA: &str = "noir-font-placement-plan-v1";
const FONT_PLACEMENT_PLAN_ABI_REVISION: u32 = 1;
const DYNAMIC_FONT_CELL_PLAN_ABI_SCHEMA: &str = "noir-dynamic-font-cell-plan-v1";
const DYNAMIC_FONT_CELL_PLAN_ABI_REVISION: u32 = 1;
const VISUAL_LANGUAGE_PLAN_ABI_SCHEMA: &str = "noir-visual-language-plan-v1";
const VISUAL_LANGUAGE_PLAN_ABI_REVISION: u32 = 1;
const ROUNDED_SURFACE_PLAN_ABI_SCHEMA: &str = "noir-rounded-surface-plan-v1";
const ROUNDED_SURFACE_PLAN_ABI_REVISION: u32 = 1;
const SHADOW_SURFACE_PLAN_ABI_SCHEMA: &str = "noir-shadow-surface-plan-v1";
const SHADOW_SURFACE_PLAN_ABI_REVISION: u32 = 1;
const NAVIGATION_SELECTION_PLAN_ABI_SCHEMA: &str = "noir-navigation-selection-plan-v1";
const NAVIGATION_SELECTION_PLAN_ABI_REVISION: u32 = 1;
const OVERLAY_STATE_PLAN_ABI_SCHEMA: &str = "noir-overlay-state-plan-v1";
const OVERLAY_STATE_PLAN_ABI_REVISION: u32 = 1;
const MODAL_FOCUS_SUBGRAPH_ABI_SCHEMA: &str = "noir-modal-focus-subgraph-v1";
const MODAL_FOCUS_SUBGRAPH_ABI_REVISION: u32 = 1;
const MODAL_FOCUS_VISUAL_PLAN_ABI_SCHEMA: &str = "noir-modal-focus-visual-plan-v1";
const MODAL_FOCUS_VISUAL_PLAN_ABI_REVISION: u32 = 1;
const MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_SCHEMA: &str = "noir-material-observability-workbench-plan-v1";
const MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_REVISION: u32 = 1;
const FOCUS_RING_HALO_PX: f32 = 3.0;
const FOCUS_RING_THICKNESS_PX: f32 = 2.0;
const FOCUS_RING_COLOR: [f32; 4] = [0.36, 0.72, 1.0, 1.0];

#[derive(Debug, Deserialize)]
struct Scene {
    abi_contracts: AbiContracts,
    #[serde(default)] build_attestation: Option<BuildAttestation>,
    #[serde(default)] state: HashMap<String, i64>,
    #[serde(default)] state_slots: Vec<StateSlot>,
    resource_budget: ResourceBudget,
    layout_plan: Vec<LayoutEntry>,
    #[serde(default)] glyph_placement_plan: Vec<GlyphPlacementEntry>,
    #[serde(default)] glyph_draw_packets: Vec<GlyphDrawPacketEntry>,
    #[serde(default)] subgroup_packet_plan: Vec<SubgroupPacketEntry>,
    #[serde(default)] packet_activity_contract: Option<PacketActivityContract>,
    #[serde(default)] packet_worklists: Vec<PacketWorklistEntry>,
    event_map: Vec<EventBinding>,
    // Mandatory compiler output: each pointer target owns one finite release track.
    // The host admits only the canonical v1 80ms ease-out form below.
    animation_tracks: Vec<AnimationTrack>,
    actions: HashMap<String, ActionPlan>,
    #[serde(default)] action_slots: Vec<ActionSlot>,
    #[serde(default)] transactions: Vec<TransactionPlan>,
    #[serde(default)] command_matchers: Vec<CommandMatcherEntry>,
    #[serde(default)] frame_schedule: Vec<FrameTask>,
    #[serde(default)] frame_coalesced_batches: Vec<FrameCoalescedBatch>,
    render_schedules: Vec<RenderSchedule>,
    #[serde(default)] focus_graph: FocusGraph,
    #[serde(default)] keyboard_map: KeyboardMap,
    #[serde(default)] keyboard_command_map: KeyboardCommandMap,
    #[serde(default)] text_field_visuals: Vec<TextFieldVisual>,
    #[serde(default)] virtual_list_plans: Vec<VirtualListPlan>,
    #[serde(default)] list_interaction_plans: Vec<ListInteractionPlan>,
    #[serde(default)] row_activation_plans: Vec<RowActivationPlan>,
    #[serde(default)] scrollbar_plans: Vec<ScrollbarPlan>,
    #[serde(default)] list_navigation_plans: Vec<ListNavigationPlan>,
    log_browser_plans: Vec<LogBrowserPlan>,
    // Not serde-defaulted: every Scene must explicitly declare whether it has zero
    // assets or a proved set; missing field is never allowed to masquerade as v1.
    font_assets: Vec<FontAssetPlan>,
    #[serde(deserialize_with = "deserialize_dynamic_font_cell_plan_option")]
    dynamic_font_cell_plan: Option<DynamicFontCellPlan>,
    // Mandatory compiler-owned canvas contract. Host never infers visual scale from layouts.
    visual_language_plan: VisualLanguagePlan,
    #[serde(deserialize_with = "deserialize_rounded_surface_plan_option")]
    rounded_surface_plan: Option<RoundedSurfacePlan>,
    #[serde(deserialize_with = "deserialize_shadow_surface_plan_option")]
    shadow_surface_plan: Option<ShadowSurfacePlan>,
    #[serde(deserialize_with = "deserialize_navigation_selection_plan_option")]
    navigation_selection_plan: Option<NavigationSelectionPlan>,
    #[serde(deserialize_with = "deserialize_overlay_state_plan_option")]
    overlay_state_plan: Option<OverlayStatePlan>,
    // Explicit compiler marker: ordinary static overlay primitives remain compatible;
    // only a lowered material-overlay-state may require the v1 transition plan.
    overlay_state_required: bool,
    #[serde(deserialize_with = "deserialize_modal_focus_subgraph_plan_option")]
    modal_focus_subgraph_plan: Option<ModalFocusSubgraphPlan>,
    #[serde(default)]
    modal_focus_subgraph_required: bool,
    #[serde(deserialize_with = "deserialize_modal_focus_visual_plan_option")]
    modal_focus_visual_plan: Option<ModalFocusVisualPlan>,
    #[serde(default)]
    modal_focus_visual_required: bool,
    #[serde(deserialize_with = "deserialize_material_observability_workbench_plan_option")]
    material_observability_workbench_plan: Option<MaterialObservabilityWorkbenchPlan>,
    #[serde(default)]
    material_observability_workbench_required: bool,
}

#[derive(Debug, Deserialize)]
struct AbiContract { schema: String, revision: u32 }
#[derive(Debug, Deserialize)]
struct AbiContracts {
    virtual_list_plan: AbiContract,
    row_activation_plan: AbiContract,
    scrollbar_plan: AbiContract,
    list_navigation_plan: AbiContract,
    log_browser_plan: AbiContract,
    font_asset_plan: AbiContract,
    font_placement_plan: AbiContract,
    dynamic_font_cell_plan: AbiContract,
    visual_language_plan: AbiContract,
    rounded_surface_plan: AbiContract,
    shadow_surface_plan: AbiContract,
    navigation_selection_plan: AbiContract,
    overlay_state_plan: AbiContract,
    modal_focus_subgraph: AbiContract,
    modal_focus_visual_plan: AbiContract,
    material_observability_workbench_plan: AbiContract,
}

#[derive(Debug, Deserialize)]
struct VisualCanvas { width: f32, height: f32, margin: f32 }

#[derive(Debug, Deserialize)]
struct VisualLanguagePlan {
    abi_schema: String,
    abi_revision: u32,
    preset: String,
    canvas: VisualCanvas,
}

#[derive(Debug, Deserialize)]
struct RoundedSurfacePlan {
    abi_schema: String,
    abi_revision: u32,
    aa_width_px: f32,
    surfaces: Vec<RoundedSurfaceEntry>,
}
#[derive(Debug, Deserialize)]
struct RoundedSurfaceEntry {
    id: String,
    instance_offset: usize,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    radius_px: f32,
    aa_width_px: f32,
}
#[derive(Deserialize)]
#[serde(untagged)]
enum RoundedSurfacePlanWire { Plan(RoundedSurfacePlan), Disabled(bool) }
fn deserialize_rounded_surface_plan_option<'de, D>(deserializer: D) -> std::result::Result<Option<RoundedSurfacePlan>, D::Error>
where D: Deserializer<'de> {
    match RoundedSurfacePlanWire::deserialize(deserializer)? {
        RoundedSurfacePlanWire::Plan(plan) => Ok(Some(plan)),
        RoundedSurfacePlanWire::Disabled(false) => Ok(None),
        RoundedSurfacePlanWire::Disabled(true) => Err(serde::de::Error::custom("rounded_surface_plan may be an object or false, never true")),
    }
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GpuRoundedSurfaceMeta { radius_px: f32, aa_width_px: f32, width_px: f32, height_px: f32 }

#[derive(Debug, Deserialize)]
struct ShadowSurfacePlan {
    abi_schema: String,
    abi_revision: u32,
    layers: Vec<ShadowSurfaceEntry>,
}
#[derive(Debug, Deserialize)]
struct ShadowSurfaceEntry {
    id: String,
    source_id: String,
    source_instance_offset: usize,
    elevation: u32,
    layer: u32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    radius_px: f32,
    blur_px: f32,
    opacity: f32,
}
#[derive(Deserialize)]
#[serde(untagged)]
enum ShadowSurfacePlanWire { Plan(ShadowSurfacePlan), Disabled(bool) }
fn deserialize_shadow_surface_plan_option<'de, D>(deserializer: D) -> std::result::Result<Option<ShadowSurfacePlan>, D::Error>
where D: Deserializer<'de> {
    match ShadowSurfacePlanWire::deserialize(deserializer)? {
        ShadowSurfacePlanWire::Plan(plan) => Ok(Some(plan)),
        ShadowSurfacePlanWire::Disabled(false) => Ok(None),
        ShadowSurfacePlanWire::Disabled(true) => Err(serde::de::Error::custom("shadow_surface_plan may be an object or false, never true")),
    }
}

#[derive(Clone, Debug, Deserialize)]
struct NavigationSelectionDestination {
    id: String,
    event_node: String,
    action: String,
    action_slot_index: usize,
    target_value: i64,
    instance_offset: usize,
    selected_color: [f32; 4],
    unselected_color: [f32; 4],
    tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Deserialize)]
struct NavigationSelectionPlan {
    abi_schema: String,
    abi_revision: u32,
    rail_id: String,
    state: String,
    state_index: usize,
    initial_destination: String,
    initial_value: i64,
    destinations: Vec<NavigationSelectionDestination>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum NavigationSelectionPlanWire { Plan(NavigationSelectionPlan), Disabled(bool) }
fn deserialize_navigation_selection_plan_option<'de, D>(deserializer: D) -> std::result::Result<Option<NavigationSelectionPlan>, D::Error>
where D: Deserializer<'de> {
    match NavigationSelectionPlanWire::deserialize(deserializer)? {
        NavigationSelectionPlanWire::Plan(plan) => Ok(Some(plan)),
        NavigationSelectionPlanWire::Disabled(false) => Ok(None),
        NavigationSelectionPlanWire::Disabled(true) => Err(serde::de::Error::custom("navigation_selection_plan may be an object or false, never true")),
    }
}

#[derive(Clone, Debug, Deserialize)]
struct OverlayStateEntry {
    id: String,
    state: String,
    state_index: usize,
    initial_visible: i64,
    open_action: String,
    close_actions: Vec<String>,
    event_slots: Vec<usize>,
    instance_offsets: Vec<usize>,
    glyph_slots: Vec<usize>,
    tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Deserialize)]
struct OverlayStatePlan {
    abi_schema: String,
    abi_revision: u32,
    entries: Vec<OverlayStateEntry>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum OverlayStatePlanWire { Plan(OverlayStatePlan), Disabled(bool) }
fn deserialize_overlay_state_plan_option<'de, D>(deserializer: D) -> std::result::Result<Option<OverlayStatePlan>, D::Error>
where D: Deserializer<'de> {
    match OverlayStatePlanWire::deserialize(deserializer)? {
        OverlayStatePlanWire::Plan(plan) => Ok(Some(plan)),
        OverlayStatePlanWire::Disabled(false) => Ok(None),
        OverlayStatePlanWire::Disabled(true) => Err(serde::de::Error::custom("overlay_state_plan may be an object or false, never true")),
    }
}

#[derive(Clone, Debug, Deserialize)]
struct ModalFocusSubgraphEntry {
    id: String,
    state: String,
    state_index: usize,
    restore_event_slot: usize,
    focus_event_slots: Vec<usize>,
    next_slots: Vec<usize>,
    previous_slots: Vec<usize>,
    allowed_event_slots: Vec<usize>,
    tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Deserialize)]
struct ModalFocusSubgraphPlan {
    abi_schema: String,
    abi_revision: u32,
    entries: Vec<ModalFocusSubgraphEntry>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ModalFocusSubgraphPlanWire { Plan(ModalFocusSubgraphPlan), Disabled(bool) }
fn deserialize_modal_focus_subgraph_plan_option<'de, D>(deserializer: D) -> std::result::Result<Option<ModalFocusSubgraphPlan>, D::Error>
where D: Deserializer<'de> {
    match ModalFocusSubgraphPlanWire::deserialize(deserializer)? {
        ModalFocusSubgraphPlanWire::Plan(plan) => Ok(Some(plan)),
        ModalFocusSubgraphPlanWire::Disabled(false) => Ok(None),
        ModalFocusSubgraphPlanWire::Disabled(true) => Err(serde::de::Error::custom("modal_focus_subgraph_plan may be an object or false, never true")),
    }
}

// Every entry is one independently addressable outline quad. Its source offset is
// a reverse witness into the frozen Event Map; host never discovers focus geometry.
#[derive(Clone, Debug, Deserialize)]
struct ModalFocusVisualEntry {
    id: String,
    focus_event_slot: usize,
    source_instance_offset: usize,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    radius_px: f32,
    thickness_px: f32,
    color: [f32; 4],
    tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Deserialize)]
struct ModalFocusVisualPlan {
    abi_schema: String,
    abi_revision: u32,
    entries: Vec<ModalFocusVisualEntry>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ModalFocusVisualPlanWire { Plan(ModalFocusVisualPlan), Disabled(bool) }
fn deserialize_modal_focus_visual_plan_option<'de, D>(deserializer: D) -> std::result::Result<Option<ModalFocusVisualPlan>, D::Error>
where D: Deserializer<'de> {
    match ModalFocusVisualPlanWire::deserialize(deserializer)? {
        ModalFocusVisualPlanWire::Plan(plan) => Ok(Some(plan)),
        ModalFocusVisualPlanWire::Disabled(false) => Ok(None),
        ModalFocusVisualPlanWire::Disabled(true) => Err(serde::de::Error::custom("modal_focus_visual_plan may be an object or false, never true")),
    }
}

// A workbench is a closed composition of one Material rail and three resident
// static view endpoints. Its wire fields are pointer lists, never runtime IDs.
#[derive(Clone, Debug, Deserialize)]
struct MaterialObservabilityWorkbenchView {
    destination_id: String,
    event_slot: usize,
    target_value: i64,
    view_root_id: String,
    node_ids: Vec<String>,
    instance_offsets: Vec<usize>,
    instance_alphas: Vec<f32>,
    glyph_slots: Vec<usize>,
    event_slots: Vec<usize>,
    tile_ids: Vec<usize>,
}
#[derive(Clone, Debug, Deserialize)]
struct MaterialObservabilityWorkbenchPlan {
    abi_schema: String,
    abi_revision: u32,
    id: String,
    rail_id: String,
    state: String,
    state_index: usize,
    systems_list_id: String,
    systems_view_id: String,
    initial_view: String,
    initial_value: i64,
    views: Vec<MaterialObservabilityWorkbenchView>,
}
#[derive(Deserialize)]
#[serde(untagged)]
enum MaterialObservabilityWorkbenchPlanWire { Plan(MaterialObservabilityWorkbenchPlan), Disabled(bool) }
fn deserialize_material_observability_workbench_plan_option<'de, D>(deserializer: D) -> std::result::Result<Option<MaterialObservabilityWorkbenchPlan>, D::Error>
where D: Deserializer<'de> {
    match MaterialObservabilityWorkbenchPlanWire::deserialize(deserializer)? {
        MaterialObservabilityWorkbenchPlanWire::Plan(plan) => Ok(Some(plan)),
        MaterialObservabilityWorkbenchPlanWire::Disabled(false) => Ok(None),
        MaterialObservabilityWorkbenchPlanWire::Disabled(true) => Err(serde::de::Error::custom("material_observability_workbench_plan may be an object or false, never true")),
    }
}

// The shadow shader samples a source-shaped SDF inside a larger immutable quad.
// `[radius, blur, source_width, source_height]` is deliberately 16 bytes like
// rounded metadata, but indexed by shadow layer rather than UI instance slot.
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GpuShadowSurfaceMeta { radius_px: f32, blur_px: f32, source_width_px: f32, source_height_px: f32 }

// The focus outline shader consumes one immutable recipe per preallocated ring.
// Alpha remains exclusively in the independently patchable QuadInstance color lane.
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GpuFocusRingMeta { radius_px: f32, thickness_px: f32, width_px: f32, height_px: f32 }

#[derive(Debug, Deserialize)]
struct BuildAttestation {
    schema: String,
    source_fingerprint_fnv1a64: String,
    compiler_abi: String,
    scene_json_abi: String,
}

#[derive(Debug, Deserialize)]
struct ResourceBudget { instance_capacity: usize, glyph_capacity: usize }

#[derive(Clone, Debug, Deserialize)]
struct FontAssetPlan {
    abi_schema: String,
    abi_revision: u32,
    face_id: String,
    renderer_kind: String,
    manifest_path: String,
    atlas_path: String,
    font_sha256: String,
    atlas_sha256: String,
    atlas_width: u32,
    atlas_height: u32,
    atlas_channels: u32,
    pixel_size: u32,
    line_height: u32,
    glyph_domain_first: u32,
    glyph_domain_count: u32,
    atlas_page: u32,
    activation: String,
}

#[derive(Debug, Deserialize)]
struct DynamicFontCellPlan {
    abi_schema: String,
    abi_revision: u32,
    face_id: String,
    manifest_path: String,
    atlas_path: String,
    font_sha256: String,
    atlas_sha256: String,
    atlas_width: u32,
    atlas_height: u32,
    atlas_channels: u32,
    atlas_page: u32,
    coverage_policy: String,
    advance_policy: String,
    fixed_advance: f32,
    glyph_domain_first: u32,
    glyph_domain_count: u32,
    tables: Vec<DynamicFontCellTable>,
}
#[derive(Debug, Deserialize)]
struct DynamicFontCellTable {
    table_id: String,
    list_id: String,
    register_width: usize,
    physical_slots: usize,
    placement_slots: Vec<usize>,
    glyph_word_offsets: Vec<usize>,
    cell_uv: Vec<[f32; 4]>,
    cell_advance: Vec<f32>,
    tile_ids: Vec<usize>,
    packet_worklist_index: usize,
}
#[derive(Deserialize)]
#[serde(untagged)]
enum DynamicFontCellPlanWire { Plan(DynamicFontCellPlan), Disabled(bool) }
fn deserialize_dynamic_font_cell_plan_option<'de, D>(deserializer: D) -> std::result::Result<Option<DynamicFontCellPlan>, D::Error>
where D: Deserializer<'de> {
    match DynamicFontCellPlanWire::deserialize(deserializer)? {
        DynamicFontCellPlanWire::Plan(plan) => Ok(Some(plan)),
        DynamicFontCellPlanWire::Disabled(false) => Ok(None),
        DynamicFontCellPlanWire::Disabled(true) => Err(serde::de::Error::custom("dynamic_font_cell_plan may be an object or false, never true")),
    }
}

#[derive(Debug, Deserialize)]
struct FontManifest {
    schema: String,
    revision: u32,
    face_id: String,
    renderer_kind: String,
    font_sha256: String,
    atlas_sha256: String,
    glyph_count: u32,
    #[serde(default)] coverage_policy: String,
    #[serde(default)] advance_policy: String,
    #[serde(default)] fixed_advance: f32,
    atlas: FontManifestAtlas,
    metrics: FontManifestMetrics,
    glyphs: Vec<FontManifestGlyph>,
}
#[derive(Debug, Deserialize)]
struct FontManifestAtlas { width: u32, height: u32, channels: u32, mode: String }
#[derive(Debug, Deserialize)]
struct FontManifestMetrics { pixel_size: u32, line_height: u32 }
#[derive(Clone, Debug, Deserialize)]
struct FontManifestGlyph {
    glyph_id: u32,
    #[serde(default)] codepoint: u32,
    #[serde(default)] character: String,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    advance: f32,
}

struct VerifiedFontAsset {
    plan: FontAssetPlan,
    atlas_bytes: Vec<u8>,
    manifest_path: PathBuf,
    atlas_path: PathBuf,
    glyphs: Vec<FontManifestGlyph>,
}
struct VerifiedDynamicFontCellAsset {
    atlas_bytes: Vec<u8>,
    manifest_path: PathBuf,
    atlas_path: PathBuf,
    glyphs: Vec<FontManifestGlyph>,
}
struct RegisteredDynamicFontAtlas {
    view: wgpu::TextureView,
    _texture: wgpu::Texture,
}
struct RegisteredFontAtlas {
    face_id: String,
    atlas_page: u32,
    width: u32,
    height: u32,
    atlas_sha256: String,
    glyphs: Vec<FontManifestGlyph>,
    view: wgpu::TextureView,
    _texture: wgpu::Texture,
}
#[derive(Clone, Debug, Deserialize)]
struct VirtualScrollPatch {
    offset: usize,
    y: f32,
}
#[derive(Clone, Debug, Deserialize)]
struct VirtualScrollScissor {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
}
#[derive(Clone, Debug, Deserialize)]
struct VirtualGlyphIdPatch {
    offset: usize,
    glyph_id: u32,
}
#[derive(Clone, Debug, Deserialize)]
struct VirtualScrollTransition {
    from_slot: usize,
    to_slot: usize,
    visible_row_tile_ids: Vec<usize>,
    instance_y_patches: Vec<VirtualScrollPatch>,
    glyph_y_patches: Vec<VirtualScrollPatch>,
    #[serde(default)] glyph_id_patches: Vec<VirtualGlyphIdPatch>,
    scissor: VirtualScrollScissor,
}
#[derive(Clone, Debug, Deserialize)]
struct DataRegisterTable {
    id: String,
    capacity: usize,
    #[serde(rename = "register-width")]
    register_width: usize,
    seed: String,
    #[serde(rename = "atlas-page")]
    atlas_page: u32,
    #[serde(rename = "font-face")]
    font_face: Option<String>,
}
#[derive(Clone, Debug)]
struct CompiledDataRegisterTable {
    id: String,
    register_width: usize,
    atlas_page: u32,
    glyph_ids: Vec<u32>,
}

// Compact data registers accept a compiler-proved ASCII subset. Digits select the
// existing page-0 legacy atlas; uppercase letters and spaces select page 1. The
// glyph placement address and quad stay fixed, so this is a glyph-ID patch only.
fn legacy_register_glyph_id(ch: char) -> Result<u32> {
    match ch {
        ' ' => Ok(1u32 << 16),
        '0'..='9' => Ok(ch as u32 - '0' as u32),
        'A'..='Z' => Ok((1u32 << 16) | (1 + (ch as u32 - 'A' as u32))),
        _ => anyhow::bail!("compact data register only admits uppercase ASCII, digits, and spaces"),
    }
}

fn tabular_body_glyph_id(ch: char) -> Result<u32> {
    let index = match ch {
        ' ' => 0,
        '0'..='9' => 1 + (ch as u32 - '0' as u32),
        'A'..='Z' => 11 + (ch as u32 - 'A' as u32),
        _ => anyhow::bail!("page-3 tabular register only admits TABULAR_BODY_V1: space, digits, uppercase letters"),
    };
    Ok((3u32 << 16) | index)
}

fn compact_register_glyphs(value: &str, register_width: usize, atlas_page: u32) -> Result<Vec<u32>> {
    anyhow::ensure!(value.len() <= register_width, "compact data register exceeds fixed width");
    let encoder: fn(char) -> Result<u32> = match atlas_page {
        1 => legacy_register_glyph_id,
        3 => tabular_body_glyph_id,
        _ => anyhow::bail!("compact data register uses unsupported fixed atlas page {atlas_page}"),
    };
    let mut glyphs = value.chars().map(encoder).collect::<Result<Vec<_>>>()?;
    glyphs.resize(register_width, if atlas_page == 3 { 3u32 << 16 } else { 1u32 << 16 });
    Ok(glyphs)
}

#[derive(Deserialize)]
#[serde(untagged)]
enum DataRegisterTableWire {
    Table(DataRegisterTable),
    Disabled(bool),
}

fn deserialize_data_register_table_option<'de, D>(deserializer: D) -> std::result::Result<Option<DataRegisterTable>, D::Error>
where
    D: Deserializer<'de>,
{
    match DataRegisterTableWire::deserialize(deserializer)? {
        DataRegisterTableWire::Table(table) => Ok(Some(table)),
        DataRegisterTableWire::Disabled(false) => Ok(None),
        DataRegisterTableWire::Disabled(true) => Err(serde::de::Error::custom("data_register_table may be an object or false, never true")),
    }
}
#[derive(Clone, Debug, Deserialize)]
struct DeclaredDataUpdate { index: usize, value: String }
#[derive(Clone, Debug, Deserialize)]
struct DeclaredDataUpdateBatch { id: String, table: String, updates: Vec<DeclaredDataUpdate> }
#[derive(Clone, Debug, Deserialize)]
struct ListInteractionNavigation { up_delta: i32, down_delta: i32, minimum_logical_row: usize, maximum_logical_row: usize }
#[derive(Clone, Debug, Deserialize)]
struct ListInteractionRender { packet_worklist_index: usize, viewport_only: bool, row_tile_rule: String }
#[derive(Clone, Debug, Deserialize)]
struct ListInteractionPlan { id: String, logical_capacity: usize, physical_slots: usize, visible_rows: usize, row_height: usize, row_color_offsets: Vec<usize>, hover_color: [f32; 4], selected_color: [f32; 4], navigation: ListInteractionNavigation, render: ListInteractionRender }
#[derive(Clone, Debug)]
struct CompiledListInteractionPlan { list_index: usize, row_color_offsets: Vec<usize>, hover_color: [f32; 4], selected_color: [f32; 4], minimum_logical_row: usize, maximum_logical_row: usize }

#[derive(Clone, Debug, Deserialize)]
struct RowActivationPlan {
    abi_schema: String,
    abi_revision: u32,
    list_id: String,
    action_id: String,
    action_slot_index: usize,
    activate_batch_id: String,
    tile_mask: u64,
    packet_worklist_index: usize,
    strategy_id: String,
    physical_slot_rule: String,
}

#[derive(Clone, Debug)]
struct CompiledRowActivationPlan {
    list_index: usize,
    action_slot_index: usize,
    activate_batch_id: String,
    tile_mask: u64,
    packet_worklist_index: usize,
}
#[derive(Clone, Debug, Deserialize)]
struct ScrollbarTrack { x: f32, y: f32, width: f32, height: f32 }
#[derive(Clone, Debug, Deserialize)]
struct ScrollbarPlan {
    abi_schema: String,
    abi_revision: u32,
    id: String,
    list_id: String,
    track_id: String,
    thumb_id: String,
    track_instance_offset: usize,
    thumb_instance_offset: usize,
    track: ScrollbarTrack,
    thumb_height: f32,
    max_viewport: usize,
    tile_ids: Vec<usize>,
    packet_worklist_index: usize,
    physical_slot_rule: String,
}
#[derive(Clone, Debug)]
struct CompiledScrollbarPlan {
    id: String,
    list_index: usize,
    thumb_instance_offset: usize,
    track_x: f32,
    track_y: f32,
    track_width: f32,
    track_height: f32,
    thumb_height: f32,
    max_viewport: usize,
    tile_ids: Vec<usize>,
    tile_mask: u64,
}
#[derive(Clone, Debug, Deserialize)]
struct ListNavigationTransition { key: String, kind: String }
#[derive(Clone, Debug, Deserialize)]
struct ListNavigationPlan {
    abi_schema: String,
    abi_revision: u32,
    id: String,
    list_id: String,
    scrollbar_id: String,
    page_step: usize,
    max_viewport: usize,
    transitions: Vec<ListNavigationTransition>,
    tile_ids: Vec<usize>,
    packet_worklist_index: usize,
    physical_slot_rule: String,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ListNavigationKey { PageUp, PageDown, Home, End }
#[derive(Clone, Debug)]
struct CompiledListNavigationPlan {
    id: String,
    list_index: usize,
    page_step: usize,
    max_viewport: usize,
    tile_mask: u64,
}

#[derive(Clone, Debug)]
struct CompiledNavigationSelectionDestination {
    id: String,
    event_slot: usize,
    action_slot_index: usize,
    target_value: i64,
    instance_offset: usize,
    selected_color: [f32; 4],
    unselected_color: [f32; 4],
    tile_mask: u64,
}
#[derive(Clone, Debug)]
struct CompiledNavigationSelectionPlan {
    rail_id: String,
    state_index: usize,
    destinations: Vec<CompiledNavigationSelectionDestination>,
    selected_index: usize,
}

#[derive(Clone, Debug)]
struct CompiledOverlayStateEntry {
    id: String,
    state_index: usize,
    open_action: String,
    close_actions: Vec<String>,
    event_slots: Vec<usize>,
    instance_offsets: Vec<usize>,
    instance_alphas: Vec<f32>,
    glyph_slots: Vec<usize>,
    shadow_indices: Vec<usize>,
    tile_mask: u64,
}

#[derive(Clone, Debug)]
struct CompiledOverlayStatePlan { entries: Vec<CompiledOverlayStateEntry> }

#[derive(Clone, Debug)]
struct CompiledModalFocusSubgraphEntry {
    id: String,
    state_index: usize,
    restore_event_slot: usize,
    focus_event_slots: Vec<usize>,
    next_slots: Vec<usize>,
    previous_slots: Vec<usize>,
    allowed_event_slots: Vec<usize>,
    tile_mask: u64,
    current_index: usize,
}

#[derive(Clone, Debug)]
struct CompiledModalFocusSubgraphPlan { entries: Vec<CompiledModalFocusSubgraphEntry> }

#[derive(Clone, Debug)]
struct CompiledModalFocusVisualEntry {
    id: String,
    modal_entry_index: usize,
    focus_event_slot: usize,
    source_instance_offset: usize,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    radius_px: f32,
    thickness_px: f32,
    color: [f32; 4],
    tile_mask: u64,
}

#[derive(Clone, Debug)]
struct CompiledModalFocusVisualPlan {
    entries: Vec<CompiledModalFocusVisualEntry>,
    // Event Map slot -> focus-ring buffer slot. The keyboard hot path indexes this
    // table directly after the compiler has proved the closed Tab subgraph.
    ring_for_event_slot: Vec<Option<usize>>,
}

#[derive(Clone, Debug)]
struct CompiledMaterialObservabilityWorkbenchView {
    destination_id: String,
    event_slot: usize,
    target_value: i64,
    view_root_id: String,
    instance_offsets: Vec<usize>,
    instance_alphas: Vec<f32>,
    glyph_slots: Vec<usize>,
    event_slots: Vec<usize>,
    shadow_indices: Vec<usize>,
    shadow_alphas: Vec<f32>,
    tile_mask: u64,
}
#[derive(Clone, Debug)]
struct CompiledMaterialObservabilityWorkbenchPlan {
    id: String,
    rail_id: String,
    state_index: usize,
    systems_list_index: usize,
    systems_view_index: usize,
    selected_index: usize,
    views: Vec<CompiledMaterialObservabilityWorkbenchView>,
    // Event Map slot -> view index. Global rail/overlay events retain None and are
    // intentionally outside the view gate.
    view_for_event_slot: Vec<Option<usize>>,
}

#[derive(Clone, Debug, Deserialize)]
struct LogAppendUpdate { index: usize, value: String }
#[derive(Clone, Debug, Deserialize)]
struct LogLevelWire { name: String, color: [f32; 4] }
#[derive(Clone, Debug, Deserialize)]
struct LogBrowserPlan {
    abi_schema: String,
    abi_revision: u32,
    id: String,
    list_id: String,
    append_batch_id: String,
    append_indices: Vec<usize>,
    append_updates: Vec<LogAppendUpdate>,
    detail_node_id: String,
    detail_glyph_offsets: Vec<usize>,
    detail_tile_ids: Vec<usize>,
    row_color_offsets: Vec<usize>,
    levels: Vec<LogLevelWire>,
    packet_worklist_index: usize,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum LogLevel { Info, Warn, Error, Debug }
#[derive(Clone, Debug)]
struct CompiledLogBrowserPlan {
    id: String,
    list_index: usize,
    append_batch_id: String,
    append_updates: Vec<LogAppendUpdate>,
    detail_glyph_offsets: Vec<usize>,
    detail_tile_mask: u64,
    row_color_offsets: Vec<usize>,
    level_colors: [[f32; 4]; 4],
    packet_worklist_index: usize,
}

#[derive(Clone, Debug, Deserialize)]
struct VirtualRowSubrange {
    first: u32,
    count: u32,
}
#[derive(Clone, Debug, Deserialize)]
struct VirtualListPlan {
    abi_schema: String,
    abi_revision: u32,
    id: String,
    capacity: usize,
    logical_capacity: usize,
    physical_slots: usize,
    recycling: bool,
    logical_data_ids: Vec<String>,
    logical_labels: Vec<String>,
    initial_ring_slots: Vec<usize>,
    #[serde(default, deserialize_with = "deserialize_data_register_table_option")]
    data_register_table: Option<DataRegisterTable>,
    data_update_batches: Vec<DeclaredDataUpdateBatch>,
    visible_rows: usize,
    row_height: usize,
    viewport_height: usize,
    row_ids: Vec<String>,
    row_layout_offsets: Vec<usize>,
    row_instance_offsets: Vec<Vec<usize>>,
    row_glyph_slots: Vec<Vec<usize>>,
    row_draw_ranges: Vec<VirtualRowSubrange>,
    row_glyph_subranges: Vec<VirtualRowSubrange>,
    visible_row_tile_ids: Vec<usize>,
    scroll_transitions: Vec<VirtualScrollTransition>,
}
#[derive(Clone, Debug)]
struct CompiledVirtualListPlan {
    id: String,
    capacity: usize,
    logical_capacity: usize,
    physical_slots: usize,
    recycling: bool,
    logical_data_ids: Vec<String>,
    logical_labels: Vec<String>,
    ring_slots: Vec<usize>,
    data_register_table: Option<CompiledDataRegisterTable>,
    data_update_batches: Vec<DeclaredDataUpdateBatch>,
    visible_rows: usize,
    row_height: usize,
    viewport_height: usize,
    row_layout_offsets: Vec<usize>,
    row_instance_offsets: Vec<Vec<usize>>,
    row_glyph_slots: Vec<Vec<usize>>,
    row_draw_ranges: Vec<VirtualRowSubrange>,
    row_glyph_subranges: Vec<VirtualRowSubrange>,
    row_base_instance_y: Vec<Vec<f32>>,
    row_base_glyph_y: Vec<Vec<f32>>,
    scroll_scissor: VirtualScrollScissor,
    visible_row_tile_ids: Vec<usize>,
    scroll_transitions: Vec<VirtualScrollTransition>,
    current_viewport_slot: usize,
}
#[derive(Debug, Deserialize)]
struct PacketActivityContract {
    packet_count: usize,
    workgroup_size: u32,
    scalar_entry: String,
    subgroup_entry: String,
    differential_required: bool,
}
#[derive(Debug, Deserialize)]
struct PacketWorklistEntry { index: usize, id: String, packet_indices: Vec<usize> }
#[derive(Clone, Debug)]
struct CompiledPacketWorklist { index: usize, id: String, packet_indices: Vec<u32> }
#[derive(Debug, Deserialize)]
struct StateSlot { index: usize, id: String, initial: i64 }
#[derive(Debug, Deserialize)]
struct ActionSlot { index: usize, id: String }
#[derive(Debug, Deserialize)]
struct TransactionPlan { index: usize, id: String, field_slots: Vec<usize>, state_indices: Vec<usize>, #[serde(default)] tile_ids: Vec<usize> }
#[derive(Debug, Deserialize)]
struct CommandMatcherEntry {
    field: String,
    focus_slot: usize,
    literal: String,
    length: usize,
    packed: u64,
    action: String,
    action_index: usize,
    #[serde(default)] tile_ids: Vec<usize>,
}

#[derive(Debug, Default, Deserialize)]
struct FocusGraph {
    #[serde(default)] entries: Vec<FocusEntry>,
    #[serde(default = "default_focus_initial_slot")] initial_slot: i32,
}
fn default_focus_initial_slot() -> i32 { -1 }

#[derive(Debug, Default, Deserialize)]
struct KeyboardMap {
    #[serde(default)] fields: Vec<KeyboardField>,
    #[serde(default)] transitions: Vec<KeyboardTransition>,
}
#[derive(Debug, Default, Deserialize)]
struct KeyboardCommandMap { #[serde(default)] transitions: Vec<KeyboardCommandTransition> }
#[derive(Debug, Deserialize)]
struct KeyboardCommandTransition {
    focus_slot: usize,
    key: String,
    kind: String,
    #[serde(default)] action: Option<String>,
    #[serde(default)] action_index: Option<usize>,
    #[serde(default)] transaction_index: Option<usize>,
    #[serde(default)] target_state: Option<String>,
    #[serde(default)] target_state_index: Option<usize>,
    #[serde(default)] tile_ids: Vec<usize>,
}
#[derive(Debug, Deserialize)]
struct DigitRegister {
    radix: u32,
    max_digits: usize,
    initial_value: u32,
    reset_value: u32,
    maximum_value: u32,
}
#[derive(Debug, Deserialize)]
struct AsciiTextRegister {
    charset: String,
    max_chars: usize,
    initial_packed: u64,
    reset_packed: u64,
    atlas_page: u32,
}
#[derive(Debug, Deserialize)]
struct KeyboardField {
    focus_slot: usize,
    node: String,
    state: String,
    state_index: usize,
    max_chars: usize,
    #[serde(default)] charset: String,
    glyph_id_offsets: Vec<u64>,
    #[serde(default)] tile_ids: Vec<usize>,
    #[serde(default)] digit_register: Option<DigitRegister>,
    #[serde(default)] ascii_text_register: Option<AsciiTextRegister>,
}
#[derive(Debug, Deserialize)]
struct BlinkTrack { id: String, period_ms: u64, alpha: [f32; 2] }
#[derive(Debug, Deserialize)]
struct TextFieldVisual {
    focus_slot: usize,
    node: String,
    #[serde(default)] tile_ids: Vec<usize>,
    max_chars: usize,
    focus_instance_offset: usize,
    focus_alpha_offset: usize,
    placeholder_instance_offset: usize,
    placeholder_alpha_offset: usize,
    caret_instance_offset: usize,
    caret_pos_x_offset: usize,
    caret_alpha_offset: usize,
    caret_ndc_x_positions: Vec<f32>,
    blink_track: BlinkTrack,
}

#[derive(Debug, Deserialize)]
struct KeyboardTransition {
    focus_slot: usize,
    key: String,
    kind: String,
    glyph_id: u32,
    cursor_op: String,
    #[serde(default)] tile_ids: Vec<usize>,
    register_op: String,
    register_radix: u32,
    register_operand: u32,
}

#[derive(Debug, Deserialize)]
struct FocusEntry {
    slot: usize,
    node: String,
    state: String,
    state_index: usize,
    tab_index: usize,
    next_slot: usize,
    previous_slot: usize,
    #[serde(default)] tile_ids: Vec<usize>,
    instance_offset: usize,
}

#[derive(Clone, Debug)]
struct CompiledFocusEntry {
    node: String,
    next_slot: usize,
    previous_slot: usize,
    tile_mask: u64,
}
#[derive(Clone, Debug)]
struct CompiledFocusGraph {
    entries: Vec<CompiledFocusEntry>,
    current_slot: usize,
}
#[derive(Clone, Debug)]
struct CompiledDigitRegister {
    radix: u32,
    max_digits: usize,
    initial_value: u32,
    reset_value: u32,
    maximum_value: u32,
}
#[derive(Clone, Debug)]
struct CompiledAsciiTextRegister {
    max_chars: usize,
    initial_packed: u64,
    reset_packed: u64,
    atlas_page: u32,
}
#[derive(Clone, Debug)]
struct CompiledKeyboardField {
    node: String,
    max_chars: usize,
    charset: String,
    glyph_id_offsets: Vec<u64>,
    tile_mask: u64,
    digit_register: Option<CompiledDigitRegister>,
    ascii_text_register: Option<CompiledAsciiTextRegister>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum DigitRegisterOp { AppendDigit, DropLast, AppendChar, DropChar }
#[derive(Clone, Debug)]
struct CompiledKeyboardTransition {
    kind: KeyboardKind,
    glyph_id: u32,
    tile_mask: u64,
    register_op: DigitRegisterOp,
    register_radix: u32,
    register_operand: u32,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum KeyboardKind { Insert, Backspace }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum KeyboardCommandKind { Action, CommitPendingRegister, CommitGroup, Reset }
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum KeyboardCommandKey { Enter, Escape }
#[derive(Clone, Debug)]
struct CompiledKeyboardCommandTransition {
    kind: KeyboardCommandKind,
    action: Option<String>, // audit-only label; dispatch uses action_index.
    action_index: Option<usize>,
    transaction_index: Option<usize>,
    target_state_index: Option<usize>,
    tile_mask: u64,
}
#[derive(Clone, Debug)]
struct CompiledKeyboardCommandMap { transitions: Vec<Vec<CompiledKeyboardCommandTransition>> }
#[derive(Clone, Debug)]
struct CompiledTransactionPlan { id: String, field_slots: Vec<usize>, state_indices: Vec<usize>, tile_mask: u64 }
#[derive(Clone, Debug)]
struct CompiledCommandMatcher {
    focus_slot: usize,
    length: usize,
    packed: u64,
    action: String, // audit-only label
    action_index: usize,
    tile_mask: u64,
}
#[derive(Clone, Debug)]
struct CompiledTextFieldVisual {
    tile_mask: u64,
    max_chars: usize,
    focus_alpha_offset: u64,
    placeholder_alpha_offset: u64,
    caret_pos_x_offset: u64,
    caret_alpha_offset: u64,
    caret_ndc_x_positions: Vec<f32>,
    blink_period_ms: u64,
    blink_alpha: [f32; 2],
}

struct CompiledKeyboardMap {
    fields: Vec<CompiledKeyboardField>,
    // 每 slot 为 11 条固定 transition：digit-0..digit-9、backspace。
    transitions: Vec<Vec<CompiledKeyboardTransition>>,
}

#[derive(Debug, Deserialize)]
struct GlyphPlacementEntry {
    slot: usize,
    node: String,
    glyph_index: usize,
    glyph_id: u32,
    atlas_page: u32,
    glyph_byte_offset: usize,
    glyph_word_offset: usize,
    ndc_pos: [f32; 2],
    ndc_size: [f32; 2],
    atlas_uv: [f32; 4],
    advance: f32,
    dynamic: bool,
    #[serde(default)] face_id: Option<String>,
    #[serde(rename = "state")] _state: serde_json::Value,
    #[serde(default)] state_index: Option<usize>,
    #[serde(rename = "clip_stack_id")] _clip_stack_id: String,
    #[serde(rename = "clip_rect")] _clip_rect: [f32; 4],
    #[serde(rename = "z_layer")] _z_layer: i32,
    #[serde(rename = "batch_key")] _batch_key: String,
}

#[derive(Debug, Deserialize)]
struct GlyphDrawPacketEntry {
    id: String,
    atlas_page: u32,
    first_placement: u32,
    placement_count: u32,
    first_glyph_byte_offset: usize,
    glyph_byte_length: usize,
    nodes: Vec<String>,
    bounds: [f32; 4],
    #[serde(rename = "clip_stack_id")] _clip_stack_id: String,
    #[serde(rename = "clip_rect")] _clip_rect: [f32; 4],
    #[serde(rename = "z_layer")] _z_layer: i32,
    #[serde(rename = "batch_key")] _batch_key: String,
    dynamic: bool,
}

#[derive(Debug, Deserialize)]
struct LayoutEntry {
    id: String,
    #[serde(rename = "tag")] tag: String,
    ndc_pos: [f32; 2],
    ndc_size: [f32; 2],
    #[serde(default)] elevation: u32,
    color: [f32; 4],
    glyph_offset: usize,
    glyph_count: usize,
    #[serde(default)] atlas_page: u32,
    #[serde(default)] glyph_ids: Vec<u32>,
    #[serde(default)] glyph_advances: Vec<f32>,
    #[serde(rename = "instance_offset")] _instance_offset: usize,
}

#[derive(Debug, Deserialize)]
struct EventBinding {
    slot: usize,
    node: String,
    #[serde(rename = "action")] _action: Option<String>,
    #[serde(default)] action_index: Option<usize>,
    #[serde(default)] transaction_op: Option<String>,
    #[serde(default)] transaction_index: Option<usize>,
    x: f32, y: f32, width: f32, height: f32,
    instance_offset: usize,
    base_color: [f32; 4], hover_color: [f32; 4], pressed_color: [f32; 4],
    base_pos: [f32; 2], pressed_pos: [f32; 2],
}

#[derive(Clone, Debug, Deserialize)]
struct AnimationDamage {
    kind: String,
    node: String,
    x: f32, y: f32, width: f32, height: f32,
    instance_offset: usize,
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
    damage: AnimationDamage,
}

#[derive(Clone, Debug, Deserialize)]
struct StateWrite { state: String, state_index: usize, op: String, value: i64 }

#[derive(Clone, Debug, Deserialize)]
struct GpuUpdate { kind: String, node: String, state: String, state_index: usize, offset: usize, byte_length: usize, glyph_count: usize, #[serde(default)] glyph_id_offsets: Vec<usize> }

#[derive(Clone, Debug, Deserialize)]
struct InstanceUpdate { node: String, state: String, state_index: usize, offset: usize, byte_length: usize, field: String, scale: f32 }

#[derive(Clone, Debug, Deserialize)]
struct ActionPlan {
    action_index: usize,
    #[serde(default)] writes: Vec<StateWrite>,
    #[serde(default)] gpu_updates: Vec<GpuUpdate>,
    #[serde(default)] instance_updates: Vec<InstanceUpdate>,
    #[serde(default)] tile_ids: Vec<usize>,
}

#[derive(Debug, Deserialize)]
struct FrameTask {
    id: String,
    kind: String,
    priority: i32,
    #[serde(default)] writes: Vec<ByteRange>,
    #[serde(default)] tile_ids: Vec<usize>,
    #[serde(default = "default_no_packet_worklist_index")] packet_worklist_index: usize,
    // For transaction-like tasks, the compiler also preserves the constituent
    // local slots used to prove a batch-local composite union.
    #[serde(default)] packet_worklist_indices: Vec<usize>,
}

fn default_no_packet_worklist_index() -> usize { 2 }

#[derive(Clone, Debug, Deserialize)]
struct ByteRange { offset: usize, byte_length: usize }

#[derive(Clone, Debug, Deserialize)]
struct FrameCoalescedWrite { task_id: String, offset: usize, byte_length: usize }

#[derive(Clone, Debug, Deserialize)]
struct FrameCoalescedElimination { task_id: String, offset: usize, byte_length: usize, winner: String }

#[derive(Clone, Debug, Deserialize)]
struct BatchConflictEdge { left: String, right: String, winner: String, #[serde(default)] overlaps: Vec<ByteRange> }

#[derive(Clone, Debug, Deserialize)]
struct BatchTaskRef { kind: String, index: usize, id: String }

#[derive(Clone, Debug, Deserialize)]
struct FrameCoalescedBatch {
    id: String,
    task_ids: Vec<String>,
    execution_order: Vec<String>,
    #[serde(default)] execution_refs: Vec<BatchTaskRef>,
    winner_writes: Vec<FrameCoalescedWrite>,
    #[serde(default)] eliminated_writes: Vec<FrameCoalescedElimination>,
    merged_tile_ids: Vec<usize>,
    #[serde(default)] conflict_edges: Vec<BatchConflictEdge>,
    #[serde(default = "default_coalesced_strategy")] strategy_id: String,
    #[serde(default)] candidate_costs: HashMap<String, f64>,
    #[serde(default)] selection_proof: Option<StrategySelectionProof>,
    #[serde(default)] composite_worklist_index: Option<usize>,
    #[serde(default)] composite_worklist_member_indices: Vec<usize>,
    #[serde(default)] composite_worklist_packet_indices: Vec<usize>,
    #[serde(default)] batch_fusion_proof: Option<BatchFusionProof>,
}

#[derive(Clone, Debug, Deserialize)]
struct BatchFusionProof {
    member_worklist_indices: Vec<usize>,
    fused_worklist_index: usize,
    fused_packet_indices: Vec<usize>,
    fused_tile_ids: Vec<usize>,
    baseline_requests: Vec<BatchFusionBaselineRequest>,
    strategy_id: String,
}

#[derive(Clone, Debug, Deserialize)]
struct BatchFusionBaselineRequest {
    worklist_index: usize,
    tile_ids: Vec<usize>,
}

fn default_coalesced_strategy() -> String { "coalesced".to_string() }

#[derive(Clone, Debug, Deserialize)]
struct StrategySelectionProof {
    mode: String,
    #[serde(default)] profile_id: Option<String>,
    #[serde(default)] semantic_group: Option<String>,
    #[serde(default)] selection_metric: Option<String>,
    #[serde(default)] source_batch: Option<String>,
    #[serde(default)] winner: Option<String>,
    #[serde(default)] tie_break_order: Vec<String>,
    #[serde(default)] fusion_admission: Option<MultiActionFusionAdmission>,
}

#[derive(Clone, Debug, Deserialize)]
struct MultiActionFusionAdmission {
    status: String,
    reason: String,
    action_ids: Vec<String>,
    release_task: String,
    action_tile_ids: Vec<Vec<usize>>,
    packet_worklist_indices: Vec<usize>,
    strategy_id: String,
    conflict_edge_count: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CompilerStrategy { FullRedraw, PacketAware, Coalesced }

impl CompilerStrategy {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "full-redraw" => Ok(Self::FullRedraw),
            "packet-aware" => Ok(Self::PacketAware),
            "coalesced" => Ok(Self::Coalesced),
            _ => anyhow::bail!("compiler emitted unsupported strategy_id {value}"),
        }
    }
    fn id(self) -> &'static str {
        match self {
            Self::FullRedraw => "full-redraw",
            Self::PacketAware => "packet-aware",
            Self::Coalesced => "coalesced",
        }
    }
}

#[derive(Clone, Debug)]
enum CompiledTaskRef { Action(usize), Transaction(usize), Transient(usize) }

#[derive(Clone)]
struct CompiledBatch {
    id: String,
    execution_refs: Vec<CompiledTaskRef>,
    task_worklist_indices: Vec<usize>,
    // This is a compiler-proved exact union of the non-empty member worklists.
    // Batch execution must consume it directly rather than recreate a selection
    // policy from task order at runtime.
    composite_worklist_index: usize,
    composite_worklist_member_indices: Vec<usize>,
    composite_worklist_packet_indices: Vec<u32>,
    fusion_baseline_requests: Vec<CompiledFusionBaselineRequest>,
    winner_writes: Vec<FrameCoalescedWrite>,
    tile_mask: u64,
    strategy: CompilerStrategy,
}

#[derive(Clone, Copy, Debug)]
struct CompiledFusionBaselineRequest {
    tile_mask: u64,
    packet_worklist_index: usize,
}

struct EventBatchIds { press: String, activate: String, release: String }

#[derive(Clone, Copy)]
struct EventTileMasks {
    hover: u64,
    _pressed: u64,
    release: u64,
}

#[derive(Debug, Deserialize)]
struct RenderSchedule { profile_id: String, tiles: Vec<ScissorTile> }

#[derive(Debug, Deserialize)]
struct ScissorTile {
    x: f32, y: f32, width: f32, height: f32,
    draw_ranges: Vec<DrawRange>,
    glyph_packet_ranges: Vec<GlyphPacketRange>,
}

#[derive(Debug, Deserialize)]
struct SubgroupPacketEntry {
    index: usize,
    packet_id: String,
    packet_index: usize,
    first_placement: u32,
    lane_count: u32,
    subgroup_width: u32,
    active_lane_mask: u32,
    activity_word_offset: usize,
    indirect_byte_offset: u64,
    dynamic: bool,
}
#[derive(Clone, Debug)]
struct CompiledSubgroupPacket {
    index: usize,
    packet_index: usize,
    first_placement: u32,
    lane_count: u32,
    active_lane_mask: u32,
    activity_word_offset: usize,
    indirect_byte_offset: u64,
    dynamic: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GpuPacketDescriptor {
    first_placement: u32,
    lane_count: u32,
    active_lane_mask: u32,
    dynamic: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GpuDrawIndirect {
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GpuPacketWorklist {
    count: u32,
    // WGSL uniform layout aligns the named vec3<u32> field to byte 16; the
    // following vec4 array therefore starts at byte 32 and the full uniform is
    // 160 bytes. Rust mirrors both the leading and trailing alignment padding.
    _pad0: [u32; 7],
    lanes: [[u32; 4]; 8],
}
fn gpu_packet_worklist(indices: &[u32]) -> GpuPacketWorklist {
    assert!(indices.len() <= 32, "compiler worklist exceeds fixed 32-entry uniform ABI");
    let mut payload = GpuPacketWorklist::zeroed();
    payload.count = indices.len() as u32;
    for (index, packet) in indices.iter().copied().enumerate() { payload.lanes[index / 4][index % 4] = packet; }
    payload
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PacketActivityVariant { Scalar, Subgroup }

struct PacketActivityResources {
    variant: PacketActivityVariant,
    _descriptor_buffer: wgpu::Buffer,
    activity_buffer: wgpu::Buffer,
    // Every compiler worklist is prepacked at an alignment-safe offset.  Event
    // dispatch selects one fixed slot through a dynamic uniform offset; it never
    // uploads a new worklist payload on the hot path.
    _worklist_buffer: wgpu::Buffer,
    worklist_stride: u32,
    worklist_count: u32,
    indirect_buffer: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    pipeline: wgpu::ComputePipeline,
    packet_count: u32,
}

#[derive(Debug, Deserialize)]
struct GlyphPacketRange {
    packet_id: String,
    packet_index: usize,
    first_placement: u32,
    placement_count: u32,
    bounds: [f32; 4],
    dynamic: bool,
}

#[derive(Debug, Deserialize)]
struct DrawRange { first_instance: u32, instance_count: u32 }

// 与离屏 verifier 完全一致的 44-byte ABI：静态 quad 复用同一 buffer，text-run 额外带 glyph storage 地址。
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct QuadInstance {
    pos: [f32; 2],
    size: [f32; 2],
    color: [f32; 4],
    glyph_word_offset: u32,
    glyph_enabled: u32,
    glyph_count: u32,
}

// 48-byte placement ABI。quad 和 UV 都是 compiler 常量；dynamic glyph 的 atlas cell
// 唯一从 glyph storage 的固定 word offset 读取，从而 action 只覆写一个 u32 glyph_id。
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GlyphPlacementInstance {
    pos: [f32; 2],
    size: [f32; 2],
    atlas_uv: [f32; 4],
    glyph_word_offset: u32,
    atlas_page: u32,
    dynamic: u32,
    // ABI offset 44: formerly padding, now compiler-proved visibility alpha.
    alpha: f32,
}

struct GpuTimestampTimer {
    query_set: wgpu::QuerySet,
    resolve_buffer: wgpu::Buffer,
    readback_buffer: wgpu::Buffer,
    timestamp_period_ns: f32,
}

#[derive(Default)]
struct SubmittedTileStats {
    tile_count: usize,
    glyph_draw_count: usize,
    glyph_instance_count: u32,
}

fn make_gpu_timestamp_timer(device: &wgpu::Device, timestamp_period_ns: f32) -> GpuTimestampTimer {
    let query_set = device.create_query_set(&wgpu::QuerySetDescriptor {
        label: Some("noir-benchmark-timestamp-query-set"),
        ty: wgpu::QueryType::Timestamp,
        count: 2,
    });
    let resolve_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("noir-benchmark-timestamp-resolve"),
        size: 16,
        usage: wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    let readback_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("noir-benchmark-timestamp-readback"),
        size: 16,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    GpuTimestampTimer { query_set, resolve_buffer, readback_buffer, timestamp_period_ns }
}

#[derive(Serialize)]
struct BenchmarkCaseReport {
    id: String,
    execution_order: Vec<String>,
    expected_tile_mask_hex: String,
    observed_tile_mask_hex: String,
    expected_winner_write_count: usize,
    expected_winner_write_bytes: usize,
    submitted_tile_count: usize,
    submitted_glyph_draw_count: usize,
    submitted_glyph_instance_count: u32,
    cpu_event_to_submit_ns: u128,
    gpu_elapsed_ns: Option<f64>,
    expectations_match: bool,
}

#[derive(Serialize)]
struct BenchmarkReport {
    schema: String,
    renderer: String,
    profile_id: String,
    adapter_name: String,
    backend: String,
    timestamp_query_supported: bool,
    timestamp_period_ns: Option<f32>,
    cases: Vec<BenchmarkCaseReport>,
}

#[derive(Serialize)]
struct FusionExecutorMeasurement {
    request_count: usize,
    packet_activity_dispatch_count: usize,
    queue_submit_count: usize,
    tile_mask_hex: String,
    submitted_tile_count: usize,
    submitted_glyph_draw_count: usize,
    submitted_glyph_instance_count: u32,
    cpu_event_to_submit_ns: u128,
    gpu_elapsed_ns: Option<f64>,
}

#[derive(Serialize)]
struct FusionBenchmarkCaseReport {
    id: String,
    member_worklist_indices: Vec<usize>,
    fused_worklist_index: usize,
    exact_packet_union: Vec<u32>,
    expectations_match: bool,
    baseline: FusionExecutorMeasurement,
    fused: FusionExecutorMeasurement,
}

#[derive(Serialize)]
struct FusionBenchmarkReport {
    schema: String,
    renderer: String,
    profile_id: String,
    adapter_name: String,
    backend: String,
    timestamp_query_supported: bool,
    timestamp_period_ns: Option<f32>,
    cases: Vec<FusionBenchmarkCaseReport>,
}

#[derive(Clone, Copy)]
enum ReplayMode { FullRedraw, PacketAware, ActionAware, Coalesced, CompilerSelected }

impl ReplayMode {
    fn id(self) -> &'static str {
        match self {
            Self::FullRedraw => "full-redraw",
            Self::PacketAware => "packet-aware",
            Self::ActionAware => "action-aware",
            Self::Coalesced => "coalesced",
            Self::CompilerSelected => "compiler-selected",
        }
    }
}

#[derive(Serialize, Deserialize)]
struct SampleStatistics {
    sample_count: usize,
    min_ns: f64,
    median_ns: f64,
    p95_ns: f64,
    max_ns: f64,
    mean_ns: f64,
}

#[derive(Serialize, Deserialize)]
struct CompilerSelectedConsistency {
    compiler_strategy_id: String,
    proof_profile_id: String,
    proof_winner: String,
    actual_executor: String,
    expected_tile_mask_hex: String,
    observed_tile_mask_hex: String,
    expected_tile_count: usize,
    observed_tile_count: usize,
    expected_glyph_draw_count: usize,
    observed_glyph_draw_count: usize,
    expected_glyph_instance_count: u32,
    observed_glyph_instance_count: u32,
    expected_winner_write_bytes: usize,
    observed_winner_write_bytes: usize,
    self_consistent: bool,
}

#[derive(Serialize, Deserialize)]
struct ReplayMatrixRow {
    workload_id: String,
    mode: String,
    warmup_iterations: usize,
    sample_iterations: usize,
    submitted_tile_count: usize,
    submitted_glyph_draw_count: usize,
    submitted_glyph_instance_count: u32,
    expected_write_bytes: usize,
    gpu_elapsed_ns: Option<SampleStatistics>,
    cpu_event_to_submit_ns: SampleStatistics,
    #[serde(skip_serializing_if = "Option::is_none")]
    compiler_selected: Option<CompilerSelectedConsistency>,
}

#[derive(Serialize, Deserialize)]
struct ReplayMatrixReport {
    schema: String,
    renderer: String,
    profile_id: String,
    adapter_name: String,
    backend: String,
    timestamp_query_supported: bool,
    timestamp_period_ns: Option<f32>,
    warmup_iterations: usize,
    sample_iterations: usize,
    rows: Vec<ReplayMatrixRow>,
}

#[derive(Serialize, Deserialize)]
struct CalibrationManifestCase {
    batch_id: String,
    strategy_id: String,
    tile_mask_hex: String,
    tile_count: usize,
    glyph_draw_count: usize,
    glyph_instance_count: u32,
    winner_write_bytes: usize,
    gpu_median_ns: f64,
    gpu_p95_ns: f64,
}

#[derive(Serialize, Deserialize)]
struct CalibrationManifest {
    schema: String,
    profile_id: String,
    // Scene output hash remains forensic metadata; attested source identity is the admission key.
    scene_fingerprint_fnv1a64: String,
    source_fingerprint_fnv1a64: String,
    replay_report_fingerprint_fnv1a64: String,
    replay_schema: String,
    renderer: String,
    adapter_name: String,
    backend: String,
    timestamp_query_supported: bool,
    timestamp_period_ns: Option<f32>,
    warmup_iterations: usize,
    sample_iterations: usize,
    compiler_selected: Vec<CalibrationManifestCase>,
}

#[derive(Deserialize)]
struct FreshnessRegistry { registry_version: u32, profiles: Vec<FreshnessProfile> }
#[derive(Deserialize)]
struct FreshnessProfile {
    profile_id: String,
    matcher: FreshnessMatcher,
    timestamp_supported: bool,
    timestamp_period_ns: f64,
    replay_strategy_costs: FreshnessReplayCosts,
}
#[derive(Deserialize)]
struct FreshnessMatcher { backend: String, adapter: String, width: u32, height: u32 }
#[derive(Deserialize)]
struct FreshnessReplayCosts { schema: String, semantic_group: String, selection_metric: String, batches: Vec<FreshnessBatch> }
#[derive(Deserialize)]
struct FreshnessBatch { batch_id: String, candidates: Vec<FreshnessCandidate> }
#[derive(Deserialize)]
struct FreshnessCandidate { strategy_id: String, gpu_median_ns: f64, gpu_p95_ns: f64, tile_count: usize, glyph_draw_count: usize, glyph_instance_count: u32, winner_write_bytes: usize }

#[derive(Serialize)]
struct FreshnessCheck { name: String, passed: bool, detail: String }
#[derive(Serialize)]
struct FreshnessComparison {
    batch_id: String,
    strategy_id: String,
    observed_gpu_median_ns: f64,
    profile_gpu_median_ns: f64,
    median_relative_drift: f64,
    observed_gpu_p95_ns: f64,
    profile_gpu_p95_ns: f64,
    p95_relative_drift: f64,
    work_contract_matches: bool,
}
#[derive(Serialize)]
struct FreshnessDiagnostic {
    schema: String,
    status: String,
    policy: String,
    relative_drift_threshold: f64,
    minimum_samples: usize,
    checks: Vec<FreshnessCheck>,
    comparisons: Vec<FreshnessComparison>,
    note: String,
}

/// A compiler-produced renderer submission.  The event path may only select a
/// pre-admitted worklist slot; it cannot construct packet ranges at runtime.
#[derive(Clone, Copy, Debug)]
struct RenderRequest {
    tile_mask: u64,
    strategy: Option<CompilerStrategy>,
    packet_worklist_index: usize,
    scroll_list_index: Option<usize>,
    scroll_viewport_slot: Option<usize>,
}

impl RenderRequest {
    const NO_PACKETS: usize = 2;
    const ALL_PACKETS: usize = 0;

    fn no_packets(tile_mask: u64) -> Self {
        Self { tile_mask, strategy: None, packet_worklist_index: Self::NO_PACKETS, scroll_list_index: None, scroll_viewport_slot: None }
    }

    fn with_worklist(tile_mask: u64, packet_worklist_index: usize) -> Self {
        Self { tile_mask, strategy: None, packet_worklist_index, scroll_list_index: None, scroll_viewport_slot: None }
    }

    fn with_strategy(tile_mask: u64, strategy: CompilerStrategy, packet_worklist_index: usize) -> Self {
        Self { tile_mask, strategy: Some(strategy), packet_worklist_index, scroll_list_index: None, scroll_viewport_slot: None }
    }

    fn scroll(list_index: usize, viewport_slot: usize) -> Self {
        Self { tile_mask: 0, strategy: None, packet_worklist_index: Self::NO_PACKETS,
               scroll_list_index: Some(list_index), scroll_viewport_slot: Some(viewport_slot) }
    }
}

#[derive(Clone, Debug)]
struct CompiledReleaseTrack {
    id: String,
    event_slot: usize,
    instance_offset: usize,
    pos_offset: usize,
    color_offset: usize,
    duration_ms: u32,
    pos_from: [f32; 2],
    pos_to: [f32; 2],
    color_from: [f32; 4],
    color_to: [f32; 4],
    tile_mask: u64,
}

#[derive(Clone, Debug)]
struct ActiveReleaseTrack {
    track_index: usize,
    started_at: Instant,
}

struct Host {
    scene_fingerprint_fnv1a64: String,
    source_fingerprint_fnv1a64: String,
    window: Arc<Window>,
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    size: PhysicalSize<u32>,
    canvas_width: u32,
    canvas_height: u32,
    canvas_margin: f32,
    scene: Scene,
    // Compiler-proved State Slot table; event paths use only array indices. Scene.state is retained only for admission parity checks.
    state_slot_ids: Vec<String>,
    state_slot_values: Vec<i64>,
    initial_state_slot_values: Vec<i64>,
    instances: Vec<QuadInstance>,
    initial_instances: Vec<QuadInstance>,
    initial_glyph_bytes: Vec<u8>,
    placements: Vec<GlyphPlacementInstance>,
    instance_buffer: wgpu::Buffer,
    glyph_buffer: wgpu::Buffer,
    placement_buffer: wgpu::Buffer,
    unit_quad: wgpu::Buffer,
    clear_buffer: wgpu::Buffer,
    static_pipeline: wgpu::RenderPipeline,
    rounded_surface_bind_group: wgpu::BindGroup,
    _rounded_surface_buffer: wgpu::Buffer,
    shadow_pipeline: wgpu::RenderPipeline,
    shadow_surface_bind_group: wgpu::BindGroup,
    shadow_instance_buffer: wgpu::Buffer,
    shadow_instance_count: u32,
    shadow_instances: Vec<QuadInstance>,
    _shadow_surface_buffer: wgpu::Buffer,
    focus_ring_pipeline: wgpu::RenderPipeline,
    focus_ring_bind_group: wgpu::BindGroup,
    focus_ring_instance_buffer: wgpu::Buffer,
    focus_ring_instance_count: u32,
    focus_ring_instances: Vec<QuadInstance>,
    _focus_ring_meta_buffer: wgpu::Buffer,
    text_pipeline: wgpu::RenderPipeline,
    glyph_bind_group: wgpu::BindGroup,
    blit_pipeline: wgpu::RenderPipeline,
    _canvas: wgpu::Texture,
    canvas_view: wgpu::TextureView,
    blit_bind_group: wgpu::BindGroup,
    cursor: [f32; 2], hovered: Option<usize>, pressed: Option<usize>,
    // 编译器 tile IDs 在启动期归约为固定 bitmask；事件期只做按位或，没有 damage rect 或 tile 搜索。
    // Compiler action table; pointer/keyboard paths only index this Vec.
    action_slot_ids: Vec<String>,
    compiled_actions: Vec<ActionPlan>,
    compiled_transactions: Vec<CompiledTransactionPlan>,
    subgroup_packets: Vec<CompiledSubgroupPacket>,
    packet_activity: Option<PacketActivityResources>,
    _packet_activity_reference: Option<PacketActivityResources>,
    packet_activity_variant: PacketActivityVariant,
    packet_worklists: Vec<CompiledPacketWorklist>,
    keyboard_packet_worklist_indices: Vec<usize>,
    transaction_packet_worklist_indices: Vec<usize>,
    subgroup_vertex_supported: bool,
    command_matchers: Vec<CompiledCommandMatcher>,
    transient_task_ids: Vec<String>,
    action_tile_masks: HashMap<String, u64>,
    event_tile_masks: Vec<EventTileMasks>,
    coalesced_batches: HashMap<String, CompiledBatch>,
    event_batch_ids: Vec<EventBatchIds>,
    frame_task_event_slots: HashMap<String, usize>,
    // Tracks are compiler-proved one-to-one with release tasks. At runtime the only
    // mutable animation state is the start Instant for an already-indexed track.
    release_tracks: Vec<CompiledReleaseTrack>,
    active_release_tracks: Vec<ActiveReleaseTrack>,
    // Compiler-proved fixed-capacity viewport tables. Future scroll paths select
    // row-tile ranges from this table; they never measure rows or walk UI nodes.
    virtual_lists: Vec<CompiledVirtualListPlan>,
    list_interactions: Vec<CompiledListInteractionPlan>,
    list_hovered_rows: Vec<Option<usize>>,
    list_selected_rows: Vec<Option<usize>>,
    row_activation_plans: Vec<CompiledRowActivationPlan>,
    scrollbar_plans: Vec<CompiledScrollbarPlan>,
    active_scrollbar: Option<usize>,
    list_navigation_plans: Vec<CompiledListNavigationPlan>,
    navigation_selection_plan: Option<CompiledNavigationSelectionPlan>,
    overlay_state_plan: Option<CompiledOverlayStatePlan>,
    modal_focus_subgraph_plan: Option<CompiledModalFocusSubgraphPlan>,
    modal_focus_visual_plan: Option<CompiledModalFocusVisualPlan>,
    material_observability_workbench_plan: Option<CompiledMaterialObservabilityWorkbenchPlan>,
    log_browser_plans: Vec<CompiledLogBrowserPlan>,
    log_levels: Vec<Vec<LogLevel>>,
    // Registered v1 fontc atlases. They deliberately remain separate from legacy
    // atlas pages 0/1 until a later glyph-placement ABI activates page 2.
    _font_atlases: Vec<RegisteredFontAtlas>,
    _dynamic_font_cell_atlas: Option<RegisteredDynamicFontAtlas>,
    // The event loop owns a FIFO of compiler-fixed renderer requests.  This replaces
    // separate dirty-tile/worklist/strategy hand-off state, so redraw receives all
    // scheduling operands explicitly.
    pending_render: Vec<RenderRequest>,
    // Focus 环路由 compiler 固定。current_slot 是唯一可变焦点状态；Tab 事件只索引该小数组。
    focus: Option<CompiledFocusGraph>,
    keyboard: Option<CompiledKeyboardMap>,
    keyboard_commands: Option<CompiledKeyboardCommandMap>,
    keyboard_cursors: Vec<usize>,
    // 仅由 compiler 固定 transition 更新；索引与 focus slot 一一对应，绝不存字符串。
    keyboard_pending_values: Vec<u32>,
    // ascii-upper 使用每 slot 一个 packed u64（最多 8 个 ASCII byte）；不分配 String。
    keyboard_text_values: Vec<u64>,
    visuals: Option<Vec<CompiledTextFieldVisual>>,
    blink_origin: Instant,
    blink_on: bool,
    modifiers: ModifiersState,
    canvas_dirty: bool,
    gpu_timer: Option<GpuTimestampTimer>,
    adapter_name: String,
    backend_name: String,
}

impl Host {
    async fn new(window: Arc<Window>, scene: Scene, scene_dir: PathBuf, scene_fingerprint_fnv1a64: String) -> Result<Self> {
        compiler_abi_contracts(&scene)?;
        let visual_canvas = compiler_visual_language_plan(&scene)?;
        // Must complete before adapter/device/window rendering side effects. The returned
        // table has exactly one immutable metadata slot per frozen QuadInstance.
        let rounded_surface_metadata = compiler_rounded_surface_plan(&scene)?;
        let (mut shadow_instances, shadow_surface_metadata) = compiler_shadow_surface_plan(&scene)?;
        let source_fingerprint_fnv1a64 = scene.build_attestation.as_ref()
            .filter(|attestation| attestation.schema == "noir-build-attestation-v1")
            .map(|attestation| attestation.source_fingerprint_fnv1a64.clone())
            .unwrap_or_else(|| "unattested".to_string());
        if let Some(attestation) = &scene.build_attestation {
            println!("compiler build attestation: source={} compiler_abi={} scene_abi={}",
                     attestation.source_fingerprint_fnv1a64, attestation.compiler_abi, attestation.scene_json_abi);
        } else {
            println!("compiler build attestation: absent (legacy Scene)");
        }
        let size = window.inner_size();
        anyhow::ensure!(size.width == visual_canvas.width && size.height == visual_canvas.height,
                        "window {}x{} disagrees with compiler visual canvas {}x{}",
                        size.width, size.height, visual_canvas.width, visual_canvas.height);
        let mut descriptor = wgpu::InstanceDescriptor::new_without_display_handle_from_env();
        descriptor.flags |= wgpu::InstanceFlags::ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER;
        let instance = wgpu::Instance::new(descriptor);
        let surface = instance.create_surface(window.clone()).context("create wgpu surface")?;
        let adapter = instance.request_adapter(&wgpu::RequestAdapterOptions { power_preference: wgpu::PowerPreference::HighPerformance, compatible_surface: Some(&surface), force_fallback_adapter: false, apply_limit_buckets: false }).await.context("request surface adapter")?;
        let adapter_info = adapter.get_info();
        let timestamp_features = wgpu::Features::TIMESTAMP_QUERY | wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS;
        let timestamp_supported = adapter.features().contains(timestamp_features);
        let subgroup_adapter_supported = adapter.features().contains(wgpu::Features::SUBGROUP);
        // wgpu 0.20 exposes feature bits but its shipped Naga WGSL parser does not yet accept
        // `enable subgroups;`. Keep the subgroup shader source in-tree and select it only once
        // both adapter and WGSL frontend support are admitted by the toolchain.
        let subgroup_wgsl_supported = false;
        let subgroup_supported = subgroup_adapter_supported && subgroup_wgsl_supported;
        let mut requested_features = if timestamp_supported { timestamp_features } else { wgpu::Features::empty() };
        if subgroup_supported { requested_features |= wgpu::Features::SUBGROUP; }
        let (device, queue) = adapter.request_device(&wgpu::DeviceDescriptor { label: Some("noir-winit-host-device"), required_features: requested_features, required_limits: wgpu::Limits::downlevel_defaults(), experimental_features: Default::default(), memory_hints: Default::default(), trace: Default::default() }).await?;
        let caps = surface.get_capabilities(&adapter);
        let format = caps.formats.iter().copied().find(|f| f.is_srgb()).unwrap_or(caps.formats[0]);
        let config = wgpu::SurfaceConfiguration { usage: wgpu::TextureUsages::RENDER_ATTACHMENT, format, color_space: wgpu::SurfaceColorSpace::Auto, width: size.width.max(1), height: size.height.max(1), present_mode: wgpu::PresentMode::Fifo, alpha_mode: caps.alpha_modes[0], view_formats: vec![], desired_maximum_frame_latency: 2 };
        surface.configure(&device, &config);

        let verified_font_assets = compiler_font_assets(&scene, &scene_dir)?;
        let verified_dynamic_font_cells = compiler_dynamic_font_cells(&scene, &scene_dir)?;
        compiler_font_placements(&scene, &verified_font_assets)?;
        let virtual_lists = compiler_virtual_list_plans(&scene)?;
        let list_interactions = compiler_list_interaction_plans(&scene, &virtual_lists)?;
        if !virtual_lists.is_empty() {
            println!("compiler virtual lists: {}", virtual_lists.iter().map(|plan| format!("{} capacity={} viewport={}x{} row-tiles={:?}", plan.id, plan.capacity, plan.visible_rows, plan.row_height, plan.visible_row_tile_ids)).collect::<Vec<_>>().join("; "));
        }
        let (state_slot_ids, state_slot_values) = compiler_state_slots(&scene)?;
        let (action_slot_ids, compiled_actions) = compiler_action_slots(&scene)?;
        compiler_action_state_slots(&scene, &state_slot_ids)?;
        let initial_state_slot_values = state_slot_values.clone();
        let (action_tile_masks, event_tile_masks) = compiler_tile_selection(&scene)?;
        let release_tracks = compiler_release_motion_tracks(&scene, &event_tile_masks)?;
        let focus = compiler_focus_graph(&scene)?;
        let keyboard = compiler_keyboard_map(&scene, focus.as_ref())?;
        let keyboard_cursors = keyboard.as_ref().map(|map| vec![0; map.fields.len()]).unwrap_or_default();
        let keyboard_pending_values = keyboard.as_ref().map(|map| {
            map.fields.iter().map(|field| field.digit_register.as_ref().map(|register| register.initial_value).unwrap_or(0)).collect()
        }).unwrap_or_default();
        let keyboard_text_values = keyboard.as_ref().map(|map| {
            map.fields.iter().map(|field| field.ascii_text_register.as_ref().map(|register| register.initial_packed).unwrap_or(0)).collect()
        }).unwrap_or_default();
        let compiled_transactions = compiler_transactions(&scene, keyboard.as_ref())?;
        let subgroup_packets = compiler_subgroup_packets(&scene)?;
        let packet_worklists = compiler_packet_worklists(&scene, &subgroup_packets)?;
        let scrollbar_plans = compiler_scrollbar_plans(&scene, &virtual_lists, &packet_worklists)?;
        let list_navigation_plans = compiler_list_navigation_plans(&scene, &virtual_lists, &scrollbar_plans, &packet_worklists)?;
        let log_browser_plans = compiler_log_browser_plans(&scene, &virtual_lists, &list_interactions, &packet_worklists)?;
        let log_levels = log_browser_plans.iter()
            .map(|plan| vec![LogLevel::Info; virtual_lists[plan.list_index].logical_capacity])
            .collect::<Vec<_>>();
        let keyboard_packet_worklist_indices = compiler_keyboard_packet_worklists(keyboard.as_ref(), &packet_worklists)?;
        let transaction_packet_worklist_indices = compiler_transaction_packet_worklists(&compiled_transactions, &packet_worklists)?;
        println!("compiler packet worklists: {}", packet_worklists.iter().map(|w| format!("{}#{}={:?}", w.id, w.index, w.packet_indices)).collect::<Vec<_>>().join("; "));
        compiler_packet_activity_contract(&scene, &subgroup_packets)?;
        let packet_activity_differential_required = true;
        let subgroup_vertex_supported = adapter.features().contains(wgpu::Features::SUBGROUP_VERTEX);
        let command_matchers = compiler_command_matchers(&scene, keyboard.as_ref(), &compiled_actions)?;
        let keyboard_commands = compiler_keyboard_command_map(&scene, focus.as_ref(), keyboard.as_ref(), &compiled_transactions)?;
        let visuals = compiler_text_field_visuals(&scene, focus.as_ref(), keyboard.as_ref())?;
        let (coalesced_batches, event_batch_ids, frame_task_event_slots, transient_task_ids) = compiler_coalesced_batches(&scene)?;
        let navigation_selection_plan = compiler_navigation_selection_plan(&scene, &state_slot_ids, &action_slot_ids, &action_tile_masks, &event_tile_masks, &packet_worklists)?;
        let row_activation_plans = compiler_row_activation_plans(&scene, &virtual_lists, &action_slot_ids, &action_tile_masks, &coalesced_batches, &packet_worklists)?;
        println!("compiler action tile selection: {} action mask(s), {} event transient mask(s), fixed-mask=u64", action_tile_masks.len(), event_tile_masks.len());
        if let Some(graph) = &focus {
            println!("compiler focus graph: {} field(s), initial slot={}, fixed Tab ring", graph.entries.len(), graph.current_slot);
        } else {
            println!("compiler focus graph: no focusable fields");
        }
        if let Some(map) = &keyboard {
            println!("compiler keyboard map: {} field(s), {} fixed transition(s), digits+backspace only", map.fields.len(), map.transitions.len() * 11);
        } else {
            println!("compiler keyboard map: no editable focus fields");
        }
        if let Some(commands) = &keyboard_commands { println!("compiler keyboard command map: {} focus slot command set(s), Enter/Escape only", commands.transitions.len()); }
        if let Some(visuals) = &visuals { println!("compiler text field visuals: {} caret/placeholder/focus plan(s)", visuals.len()); }
        println!("compiler frame coalescing: {} verified batch(es), {} event batch pair(s)", coalesced_batches.len(), event_batch_ids.len());

        let mut instances = vec![QuadInstance::zeroed(); scene.resource_budget.instance_capacity];
        for entry in &scene.layout_plan {
            let slot = entry._instance_offset / std::mem::size_of::<QuadInstance>();
            anyhow::ensure!(slot < instances.len(), "layout {} has invalid instance slot", entry.id);
            anyhow::ensure!(entry.glyph_ids.is_empty() || entry.glyph_ids.len() == entry.glyph_count, "{} shaped glyph count mismatch", entry.id);
            anyhow::ensure!(entry.glyph_advances.is_empty() || entry.glyph_advances.len() == entry.glyph_count, "{} shaped advance count mismatch", entry.id);
            anyhow::ensure!(entry.glyph_ids.iter().all(|glyph| glyph >> 16 == entry.atlas_page), "{} glyph page disagrees with compiler atlas_page", entry.id);
            instances[slot] = QuadInstance { pos: entry.ndc_pos, size: entry.ndc_size, color: entry.color, glyph_word_offset: (entry.glyph_offset / 4) as u32, glyph_enabled: u32::from(entry.glyph_count > 0), glyph_count: entry.glyph_count as u32 };
        }
        if let Some(progress) = scene.layout_plan.iter().position(|entry| entry.id == "throughput") { instances[progress].size[0] *= 0.40; }
        let instance_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("noir-precompiled-instance-buffer"), contents: bytemuck::cast_slice(&instances), usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST });
        let glyph_bytes = initial_glyph_bytes(&scene)?;
        let static_runs = scene.layout_plan.iter().filter(|entry| !entry.glyph_ids.is_empty()).count();
        println!("compiler text resources: {static_runs} static shaped run(s), {} dynamic text-run action(s)", scene.actions.values().map(|action| action.gpu_updates.len()).sum::<usize>());
        let glyph_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("noir-placement-glyph-id-storage"), contents: &glyph_bytes, usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST });
        let mut placements = placement_instances(&scene)?;
        let overlay_state_plan = compiler_overlay_state_plan(&scene, &state_slot_ids, &action_slot_ids, &action_tile_masks, &packet_worklists, &instances, &placements)?;
        let modal_focus_subgraph_plan = compiler_modal_focus_subgraph_plan(&scene, &state_slot_ids, &overlay_state_plan, &event_tile_masks)?;
        let modal_focus_visual_plan = compiler_modal_focus_visual_plan(&scene, &overlay_state_plan, &modal_focus_subgraph_plan, &event_tile_masks, &instances)?;
        let material_observability_workbench_plan = compiler_material_observability_workbench_plan(
            &scene, &state_slot_ids, &navigation_selection_plan, &virtual_lists, &log_browser_plans, &instances, &placements,
        )?;
        apply_material_observability_workbench_initial_visibility(
            &material_observability_workbench_plan, &mut instances, &mut placements, &mut shadow_instances, &queue, &instance_buffer,
        );
        let (focus_ring_instances, focus_ring_metadata) = make_focus_ring_gpu_instances(&modal_focus_visual_plan, visual_canvas);
        if let Some(plan) = &overlay_state_plan {
            for entry in &plan.entries {
                if state_slot_values[entry.state_index] == 0 {
                    for &offset in &entry.instance_offsets {
                        instances[offset / std::mem::size_of::<QuadInstance>()].color[3] = 0.0;
                        queue.write_buffer(&instance_buffer, (offset + 28) as u64, bytemuck::bytes_of(&0.0f32));
                    }
                    for &slot in &entry.glyph_slots { placements[slot].alpha = 0.0; }
                    for &shadow_index in &entry.shadow_indices { shadow_instances[shadow_index].color[3] = 0.0; }
                }
            }
            println!("compiler overlay state initial endpoint: entries={} hidden={}", plan.entries.len(),
                     plan.entries.iter().filter(|entry| state_slot_values[entry.state_index] == 0).count());
        }
        let (tile_glyph_range_count, tile_glyph_instance_count) = validate_tile_glyph_ranges(&scene)?;
        println!("compiler glyph placement resources: {} placement instance(s), {} page-aware packet(s), ABI={} bytes", placements.len(), scene.glyph_draw_packets.len(), GLYPH_PLACEMENT_BYTES);
        println!("compiler tile glyph culling: {} scissor tile(s), {} submitted subrange(s), {} glyph instance(s)", scene.render_schedules.iter().map(|schedule| schedule.tiles.len()).sum::<usize>(), tile_glyph_range_count, tile_glyph_instance_count);
        let placement_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("noir-compiler-glyph-placement-buffer"), contents: bytemuck::cast_slice(&placements), usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST });
        let packet_activity_variant = if subgroup_supported { PacketActivityVariant::Subgroup } else { PacketActivityVariant::Scalar };
        let packet_activity = make_packet_activity_resources(&device, &glyph_buffer, &subgroup_packets, &packet_worklists, packet_activity_variant);
        let packet_activity_reference = if packet_activity_differential_required {
            make_packet_activity_resources(&device, &glyph_buffer, &subgroup_packets, &packet_worklists, PacketActivityVariant::Scalar)
        } else { None };
        if let (Some(selected), Some(reference)) = (packet_activity.as_ref(), packet_activity_reference.as_ref()) {
            run_packet_activity_differential(&device, &queue, selected, reference)?;
        }
        let unit_vertices: [[f32; 2]; 6] = [[0.0,0.0],[1.0,0.0],[0.0,1.0],[0.0,1.0],[1.0,0.0],[1.0,1.0]];
        let unit_quad = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("noir-unit-quad"), contents: bytemuck::cast_slice(&unit_vertices), usage: wgpu::BufferUsages::VERTEX });
        let clear = QuadInstance { pos: [-1.0,-1.0], size: [2.0,2.0], color: [0.008,0.012,0.025,1.0], glyph_word_offset: 0, glyph_enabled: 0, glyph_count: 0 };
        let clear_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("noir-tile-clear-quad"), contents: bytemuck::bytes_of(&clear), usage: wgpu::BufferUsages::VERTEX });
        let (rounded_surface_layout, rounded_surface_buffer, rounded_surface_bind_group) =
            make_rounded_surface_resources(&device, &rounded_surface_metadata);
        let shadow_instance_count = shadow_instances.len() as u32;
        let shadow_instance_upload = if shadow_instances.is_empty() { vec![QuadInstance::zeroed()] } else { shadow_instances };
        let shadow_instance_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("noir-immutable-shadow-instance-buffer"), contents: bytemuck::cast_slice(&shadow_instance_upload), usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        });
        let (shadow_surface_layout, shadow_surface_buffer, shadow_surface_bind_group) =
            make_shadow_surface_resources(&device, &shadow_surface_metadata);
        let focus_ring_instance_count = focus_ring_instances.len() as u32;
        let focus_ring_instance_upload = if focus_ring_instances.is_empty() { vec![QuadInstance::zeroed()] } else { focus_ring_instances.clone() };
        let focus_ring_instance_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("noir-preallocated-focus-ring-instance-buffer"),
            contents: bytemuck::cast_slice(&focus_ring_instance_upload),
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        });
        let (focus_ring_layout, focus_ring_meta_buffer, focus_ring_bind_group) =
            make_focus_ring_resources(&device, &focus_ring_metadata);

        let font_atlases = make_registered_font_atlases(&device, &queue, &verified_font_assets)?;
        let dynamic_font_cell_atlas = make_dynamic_font_cell_atlas(&device, &queue, verified_dynamic_font_cells.as_ref())?;
        let (glyph_bind_group, text_pipeline) = make_text_resources(&device, &queue, format, &glyph_buffer, &font_atlases, dynamic_font_cell_atlas.as_ref(), verified_dynamic_font_cells.as_ref())?;
        let static_pipeline = make_static_pipeline(&device, format, &rounded_surface_layout);
        let shadow_pipeline = make_shadow_pipeline(&device, format, &shadow_surface_layout);
        let focus_ring_pipeline = make_focus_ring_pipeline(&device, format, &focus_ring_layout);
        let gpu_timer = if timestamp_supported { Some(make_gpu_timestamp_timer(&device, queue.get_timestamp_period())) } else { None };
        println!("compiler subgroup packets: {} width-32 packet(s), vertex-subgroup-supported={subgroup_vertex_supported}; packet draw fallback is always ABI-equivalent", subgroup_packets.len());
        println!("compiler packet activity: gpu-driven-indirect={} variant={:?} adapter-subgroup={} wgsl-subgroup={} fixed activity-word/indirect-command ABI", packet_activity.is_some(), packet_activity_variant, subgroup_adapter_supported, subgroup_wgsl_supported);
        println!("compiler timestamp query: supported={timestamp_supported}");
        let (canvas, canvas_view, blit_bind_group, blit_pipeline) = make_canvas_and_blit(&device, format, visual_canvas.width, visual_canvas.height);
        let initial_instances = instances.clone();
        let initial_glyph_bytes = glyph_bytes.clone();
        let virtual_list_count = virtual_lists.len();
        let mut host = Self { scene_fingerprint_fnv1a64: scene_fingerprint_fnv1a64.to_string(), source_fingerprint_fnv1a64, window, surface, device, queue, config, size, canvas_width: visual_canvas.width, canvas_height: visual_canvas.height, canvas_margin: visual_canvas.margin, scene, state_slot_ids, state_slot_values, initial_state_slot_values, instances, initial_instances, initial_glyph_bytes, placements, instance_buffer, glyph_buffer, placement_buffer, unit_quad, clear_buffer, static_pipeline, rounded_surface_bind_group, _rounded_surface_buffer: rounded_surface_buffer, shadow_pipeline, shadow_surface_bind_group, shadow_instance_buffer, shadow_instance_count, shadow_instances: shadow_instance_upload, _shadow_surface_buffer: shadow_surface_buffer, focus_ring_pipeline, focus_ring_bind_group, focus_ring_instance_buffer, focus_ring_instance_count, focus_ring_instances, _focus_ring_meta_buffer: focus_ring_meta_buffer, text_pipeline, glyph_bind_group, blit_pipeline, _canvas: canvas, canvas_view, blit_bind_group,
 cursor: [0.0;2], hovered: None, pressed: None, action_slot_ids, compiled_actions, compiled_transactions, subgroup_packets, packet_activity, _packet_activity_reference: packet_activity_reference, packet_activity_variant, packet_worklists, keyboard_packet_worklist_indices, transaction_packet_worklist_indices, subgroup_vertex_supported, command_matchers, transient_task_ids, action_tile_masks, event_tile_masks, coalesced_batches, event_batch_ids, frame_task_event_slots, release_tracks, active_release_tracks: Vec::new(), virtual_lists, list_interactions, list_hovered_rows: vec![None; virtual_list_count], list_selected_rows: vec![None; virtual_list_count], row_activation_plans, scrollbar_plans, active_scrollbar: None, list_navigation_plans, navigation_selection_plan, overlay_state_plan, modal_focus_subgraph_plan, modal_focus_visual_plan, material_observability_workbench_plan, log_browser_plans, log_levels, _font_atlases: font_atlases, _dynamic_font_cell_atlas: dynamic_font_cell_atlas, pending_render: Vec::new(), focus, keyboard, keyboard_commands, keyboard_cursors, keyboard_pending_values, keyboard_text_values, visuals, blink_origin: Instant::now(), blink_on: true, modifiers: ModifiersState::empty(), canvas_dirty: true, gpu_timer, adapter_name: adapter_info.name, backend_name: format!("{:?}", adapter_info.backend) };
        host.sync_focus_visuals();
        host.execute_scene_data_update_batches()?;
        host.redraw_canvas_full();
        Ok(host)
    }

    fn encode_packet_activity(&self, encoder: &mut wgpu::CommandEncoder, worklist_index: usize) {
        if let Some(activity) = &self.packet_activity {
            let worklist = self.packet_worklists.get(worklist_index).expect("compiler worklist index admitted at startup");
            if worklist.packet_indices.is_empty() {
                println!("packet-activity-skip worklist={} index={} packets=[] reason=compiler-empty", worklist.id, worklist.index);
                return;
            }
            let dynamic_offset = (worklist_index as u32)
                .checked_mul(activity.worklist_stride)
                .expect("compiler worklist dynamic offset overflow");
            debug_assert!(worklist_index < activity.worklist_count as usize,
                          "compiler worklist index outside resident GPU table");
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor { label: Some("noir-glyph-packet-activity"), timestamp_writes: None });
            pass.set_pipeline(&activity.pipeline);
            pass.set_bind_group(0, &activity.bind_group, &[dynamic_offset]);
            pass.dispatch_workgroups(worklist.packet_indices.len() as u32, 1, 1);
            println!("packet-activity-dispatch worklist={} index={} packets={:?} workgroups={} workgroup_size=32 output=activity+indirect", worklist.id, worklist.index, worklist.packet_indices, worklist.packet_indices.len());
        }
    }

    fn overlay_event_enabled(&self, event_slot: usize) -> bool {
        let Some(plan) = self.overlay_state_plan.as_ref() else { return true; };
        let action = self.scene.event_map.get(event_slot).and_then(|event| event._action.as_deref());
        for entry in &plan.entries {
            if entry.event_slots.contains(&event_slot) {
                let visible = self.state_slot_values.get(entry.state_index).copied() == Some(1);
                return match action {
                    Some(action) if action == entry.open_action => !visible,
                    Some(action) if entry.close_actions.iter().any(|candidate| candidate == action) => visible,
                    _ => false,
                };
            }
        }
        true
    }

    fn material_observability_workbench_event_enabled(&self, event_slot: usize) -> bool {
        let Some(plan) = &self.material_observability_workbench_plan else { return true; };
        match plan.view_for_event_slot.get(event_slot).and_then(|entry| *entry) {
            Some(view_index) => plan.selected_index == view_index,
            None => true,
        }
    }

    fn hit_test(&self, point: [f32; 2]) -> Option<usize> {
        self.scene.event_map.iter().enumerate()
            .filter(|(index, e)| self.overlay_event_enabled(*index)
                    && self.material_observability_workbench_event_enabled(e.slot)
                    && point[0] >= e.x && point[0] < e.x + e.width && point[1] >= e.y && point[1] < e.y + e.height)
            .max_by_key(|(_, e)| e.slot).map(|(i,_)| i)
    }
    fn patch_color(&mut self, index: usize, color: [f32;4]) { let e=&self.scene.event_map[index]; self.instances[e.instance_offset/44].color=color; self.queue.write_buffer(&self.instance_buffer, e.instance_offset as u64 + 16, bytemuck::cast_slice(&color)); }
    fn patch_pos(&mut self, index: usize, pos: [f32;2]) { let e=&self.scene.event_map[index]; self.instances[e.instance_offset/44].pos=pos; self.queue.write_buffer(&self.instance_buffer, e.instance_offset as u64, bytemuck::cast_slice(&pos)); }

    /// Enqueue an already-lowered renderer request.  Only requests with the exact
    /// same compiler strategy and packet worklist are unioned; merging different
    /// worklists would incorrectly widen a GPU packet write scope.
    fn enqueue_render(&mut self, request: RenderRequest, source: &str) {
        if request.tile_mask == 0 && request.scroll_list_index.is_none() { return; }
        debug_assert!(request.packet_worklist_index < self.packet_worklists.len(),
                      "event path selected a non-admitted compiler worklist");
        if let Some(last) = self.pending_render.last_mut() {
            if last.strategy == request.strategy
                && last.packet_worklist_index == request.packet_worklist_index
                && last.scroll_list_index == request.scroll_list_index
                && last.scroll_viewport_slot == request.scroll_viewport_slot {
                last.tile_mask |= request.tile_mask;
                println!("render-request-coalesce {source}: mask=0x{:016x} strategy={:?} worklist={}",
                         last.tile_mask, last.strategy, last.packet_worklist_index);
                self.canvas_dirty = true;
                return;
            }
        }
        println!("render-request-enqueue {source}: mask=0x{:016x} strategy={:?} worklist={}",
                 request.tile_mask, request.strategy, request.packet_worklist_index);
        self.pending_render.push(request);
        self.canvas_dirty = true;
    }

    fn mark_dirty_tiles(&mut self, mask: u64, source: &str) {
        self.enqueue_render(RenderRequest::no_packets(mask), source);
    }

    fn patch_placement_alpha(&mut self, slot: usize, value: f32) {
        self.placements[slot].alpha = value;
        let offset = (slot * GLYPH_PLACEMENT_BYTES + 44) as u64;
        self.queue.write_buffer(&self.placement_buffer, offset, bytemuck::bytes_of(&value));
    }

    fn patch_instance_f32(&mut self, offset: u64, value: f32) {
        let slot = (offset as usize) / std::mem::size_of::<QuadInstance>();
        let lane = ((offset as usize) % std::mem::size_of::<QuadInstance>()) / 4;
        if lane == 0 { self.instances[slot].pos[0] = value; }
        if lane == 1 { self.instances[slot].pos[1] = value; }
        if lane == 7 { self.instances[slot].color[3] = value; }
        self.queue.write_buffer(&self.instance_buffer, offset, bytemuck::bytes_of(&value));
    }

    // Focus-ring quad indices are compiler emitted and validated at startup. The
    // runtime patch is therefore exactly one four-byte write into a separate buffer.
    fn patch_focus_ring_alpha(&mut self, ring_index: usize, value: f32) {
        let ring = self.focus_ring_instances.get_mut(ring_index)
            .expect("compiler focus ring index is admitted at startup");
        if (ring.color[3] - value).abs() <= f32::EPSILON { return; }
        ring.color[3] = value;
        let offset = (ring_index * std::mem::size_of::<QuadInstance>() + 28) as u64;
        self.queue.write_buffer(&self.focus_ring_instance_buffer, offset, bytemuck::bytes_of(&value));
    }

    fn focus_ring_index_for_event(&self, event_slot: usize) -> Option<usize> {
        self.modal_focus_visual_plan.as_ref()?.ring_for_event_slot.get(event_slot).and_then(|ring| *ring)
    }

    fn set_focus_ring_for_event(&mut self, event_slot: usize, value: f32) -> Option<usize> {
        let ring_index = self.focus_ring_index_for_event(event_slot)?;
        self.patch_focus_ring_alpha(ring_index, value);
        Some(ring_index)
    }

    // Overlay close is a finite preallocated write set. No element lookup or focus
    // discovery occurs: all resident ring alpha lanes are restored to the hidden endpoint.
    fn clear_all_focus_rings(&mut self) -> usize {
        let count = self.focus_ring_instances.len();
        for ring_index in 0..count { self.patch_focus_ring_alpha(ring_index, 0.0); }
        count
    }

    fn sync_focus_visuals(&mut self) -> u64 {
        let (active_slot, visuals) = match (self.focus.as_ref(), self.visuals.as_ref()) { (Some(focus), Some(visuals)) => (focus.current_slot, visuals.clone()), _ => return 0 };
        let mut mask = 0u64;
        for (slot, visual) in visuals.iter().enumerate() {
            let cursor = self.keyboard_cursors.get(slot).copied().unwrap_or(0).min(visual.max_chars);
            let active = slot == active_slot;
            self.patch_instance_f32(visual.focus_alpha_offset, if active { 0.30 } else { 0.0 });
            self.patch_instance_f32(visual.placeholder_alpha_offset, if cursor == 0 { 0.45 } else { 0.0 });
            self.patch_instance_f32(visual.caret_pos_x_offset, visual.caret_ndc_x_positions[cursor]);
            let alpha = if active && self.blink_on { visual.blink_alpha[0] } else { visual.blink_alpha[1] };
            self.patch_instance_f32(visual.caret_alpha_offset, alpha);
            if active || slot == active_slot { mask |= visual.tile_mask; }
            if active {
                println!("text-field-visual sync: slot={} cursor={} caret_ndc_x={} focus_alpha=0.30 placeholder_alpha={} caret_alpha={} mask=0x{:016x}",
                         slot, cursor, visual.caret_ndc_x_positions[cursor], if cursor == 0 { 0.45 } else { 0.0 }, alpha, visual.tile_mask);
            }
        }
        mask
    }

    fn blink_tick(&mut self) -> bool {
        let Some(visuals) = self.visuals.as_ref() else { return false; };
        let period = visuals.first().map(|visual| visual.blink_period_ms).unwrap_or(500);
        let on = ((self.blink_origin.elapsed().as_millis() / period as u128) % 2) == 0;
        if on == self.blink_on { return false; }
        self.blink_on = on;
        let mask = self.sync_focus_visuals();
        self.mark_dirty_tiles(mask, "caret-blink");
        println!("caret-blink track: phase={} mask=0x{:016x}", if on { "on" } else { "off" }, mask);
        true
    }

    fn focus_tab(&mut self, reverse: bool) {
        let Some(graph) = self.focus.as_mut() else {
            println!("focus-tab ignored: compiler Focus Graph is empty");
            return;
        };
        let from = graph.current_slot;
        let old_mask = graph.entries[from].tile_mask;
        let target = if reverse { graph.entries[from].previous_slot } else { graph.entries[from].next_slot };
        let node = graph.entries[target].node.clone();
        let mask = graph.entries[target].tile_mask;
        graph.current_slot = target;
        println!("focus-tab {}: slot {} -> {} / {} mask=0x{:016x}",
                 if reverse { "reverse" } else { "forward" }, from, target, node, mask);
        let visual_mask = self.sync_focus_visuals();
        self.mark_dirty_tiles(mask | old_mask | visual_mask, "focus-tab");
    }

    fn keyboard_transition(&mut self, key_index: usize) {
        let (slot, field, transition) = {
            let Some(focus) = self.focus.as_ref() else { return; };
            let Some(map) = self.keyboard.as_ref() else { return; };
            let slot = focus.current_slot;
            (slot, map.fields[slot].clone(), map.transitions[slot][key_index].clone())
        };
        let cursor = self.keyboard_cursors[slot];
        if field.charset == "ascii-upper" {
            let register = field.ascii_text_register.as_ref().expect("compiler ASCII proof requires text descriptor");
            let packed = self.keyboard_text_values[slot];
            match transition.kind {
                KeyboardKind::Insert if cursor < field.max_chars => {
                    debug_assert_eq!(transition.register_op, DigitRegisterOp::AppendChar);
                    let shift = (cursor * 8) as u32;
                    let next = packed | (u64::from(transition.register_operand) << shift);
                    let offset = field.glyph_id_offsets[cursor];
                    self.queue.write_buffer(&self.glyph_buffer, offset, bytemuck::bytes_of(&transition.glyph_id));
                    self.keyboard_cursors[slot] = cursor + 1;
                    self.keyboard_text_values[slot] = next;
                    println!("keyboard-transition ascii-insert: slot={} field={} cursor={}->{} glyph-id-patch [{}..{}) glyph_id={} byte={} packed=0x{:016x}->0x{:016x} register-op=append-char atlas_page={}",
                             slot, field.node, cursor, cursor + 1, offset, offset + 4, transition.glyph_id,
                             transition.register_operand, packed, next, register.atlas_page);
                }
                KeyboardKind::Insert => println!("keyboard-transition ascii-overflow: slot={} field={} cursor={} max_chars={} policy=reject", slot, field.node, cursor, field.max_chars),
                KeyboardKind::Backspace if cursor > 0 => {
                    debug_assert_eq!(transition.register_op, DigitRegisterOp::DropChar);
                    let next_cursor = cursor - 1;
                    let shift = (next_cursor * 8) as u32;
                    let next = packed & !(0xffu64 << shift);
                    let offset = field.glyph_id_offsets[next_cursor];
                    self.queue.write_buffer(&self.glyph_buffer, offset, bytemuck::bytes_of(&transition.glyph_id));
                    self.keyboard_cursors[slot] = next_cursor;
                    self.keyboard_text_values[slot] = next;
                    println!("keyboard-transition ascii-backspace: slot={} field={} cursor={}->{} glyph-id-patch [{}..{}) glyph_id={} packed=0x{:016x}->0x{:016x} register-op=drop-char", slot, field.node, cursor, next_cursor, offset, offset + 4, transition.glyph_id, packed, next);
                }
                KeyboardKind::Backspace => println!("keyboard-transition ascii-backspace-boundary: slot={} field={} cursor=0", slot, field.node),
            }
            let visual_mask = self.sync_focus_visuals();
            self.enqueue_render(RenderRequest::with_worklist(field.tile_mask | visual_mask,
                                self.keyboard_packet_worklist_indices[slot]), "keyboard-transition");
            return;
        }
        let digit_register = field.digit_register.as_ref().expect("compiler digit proof requires digit descriptor");
        let pending = self.keyboard_pending_values[slot];
        match transition.kind {
            KeyboardKind::Insert if cursor < field.max_chars => {
                debug_assert_eq!(transition.register_op, DigitRegisterOp::AppendDigit,
                                 "compiler Keyboard Map register proof was validated at startup");
                let next_pending = pending.checked_mul(transition.register_radix)
                    .and_then(|value| value.checked_add(transition.register_operand));
                let Some(next_pending) = next_pending.filter(|value| *value <= digit_register.maximum_value) else {
                    println!("keyboard-transition register-overflow: slot={} field={} key=digit-{} pending={} radix={} operand={} maximum={} policy=reject",
                             slot, field.node, key_index, pending, transition.register_radix,
                             transition.register_operand, digit_register.maximum_value);
                    return;
                };
                let offset = field.glyph_id_offsets[cursor];
                self.queue.write_buffer(&self.glyph_buffer, offset, bytemuck::bytes_of(&transition.glyph_id));
                self.keyboard_cursors[slot] = cursor + 1;
                self.keyboard_pending_values[slot] = next_pending;
                println!("keyboard-transition insert: slot={} field={} key=digit-{} cursor={}->{} glyph-id-patch [{}..{}) glyph_id={} pending={}->{} register-op=append-digit radix={} operand={}",
                         slot, field.node, key_index, cursor, cursor + 1, offset, offset + 4, transition.glyph_id,
                         pending, next_pending, transition.register_radix, transition.register_operand);
            }
            KeyboardKind::Insert => {
                println!("keyboard-transition overflow: slot={} field={} key=digit-{} cursor={} max_chars={} pending={} policy=reject",
                         slot, field.node, key_index, cursor, field.max_chars, pending);
                return;
            }
            KeyboardKind::Backspace if cursor > 0 => {
                debug_assert_eq!(transition.register_op, DigitRegisterOp::DropLast,
                                 "compiler Keyboard Map register proof was validated at startup");
                let next_pending = pending / transition.register_radix;
                let next_cursor = cursor - 1;
                let offset = field.glyph_id_offsets[next_cursor];
                // Glyph ID 0 is page-0 digit zero. This MVP defines Backspace as deterministic zero-fill.
                self.queue.write_buffer(&self.glyph_buffer, offset, bytemuck::bytes_of(&transition.glyph_id));
                self.keyboard_cursors[slot] = next_cursor;
                self.keyboard_pending_values[slot] = next_pending;
                println!("keyboard-transition backspace: slot={} field={} cursor={}->{} glyph-id-patch [{}..{}) glyph_id={} pending={}->{} register-op=drop-last radix={}",
                         slot, field.node, cursor, next_cursor, offset, offset + 4, transition.glyph_id,
                         pending, next_pending, transition.register_radix);
            }
            KeyboardKind::Backspace => {
                println!("keyboard-transition backspace-boundary: slot={} field={} cursor=0 pending={}", slot, field.node, pending);
                return;
            }
        }
        debug_assert_eq!(field.tile_mask, transition.tile_mask, "compiler Keyboard Map tile proof was validated at startup");
        let visual_mask = self.sync_focus_visuals();
        self.enqueue_render(RenderRequest::with_worklist(field.tile_mask | visual_mask,
                            self.keyboard_packet_worklist_indices[slot]), "keyboard-transition");
    }

    fn keyboard_command(&mut self, requested_key: KeyboardCommandKey) {
        let (slot, field, command) = {
            let Some(focus) = self.focus.as_ref() else { return; };
            let Some(keymap) = self.keyboard.as_ref() else { return; };
            let Some(commands) = self.keyboard_commands.as_ref() else { return; };
            let slot = focus.current_slot;
            let command = commands.transitions[slot].iter().find(|command| match requested_key {
                KeyboardCommandKey::Enter => command.kind != KeyboardCommandKind::Reset,
                KeyboardCommandKey::Escape => command.kind == KeyboardCommandKind::Reset,
            }).cloned();
            let Some(command) = command else { println!("keyboard-command ignored: slot={} has no {:?}", slot, requested_key); return; };
            (slot, keymap.fields[slot].clone(), command)
        };
        if requested_key == KeyboardCommandKey::Enter && field.charset == "ascii-upper" {
            let candidates: Vec<CompiledCommandMatcher> = self.command_matchers.iter()
                .filter(|matcher| matcher.focus_slot == slot).cloned().collect();
            if !candidates.is_empty() {
                let cursor = self.keyboard_cursors[slot];
                let packed = self.keyboard_text_values[slot];
                if let Some(matcher) = candidates.iter().find(|matcher| matcher.length == cursor && matcher.packed == packed).cloned() {
                    let action_name = self.action_slot_ids[matcher.action_index].clone();
                    let writes = match self.action_write_plan_index(matcher.action_index) {
                        Ok(writes) => writes,
                        Err(error) => { eprintln!("command-matcher action_index={} ignored: {error:#}", matcher.action_index); return; }
                    };
                    if let Err(error) = self.apply_action_winner_writes(&action_name, &writes) {
                        eprintln!("command-matcher action_index={} ignored: {error:#}", matcher.action_index);
                        return;
                    }
                    println!("command-matcher Enter: slot={} field={} packed=0x{:016x} length={} action={} action_index={} winner_writes={} mask=0x{:016x}",
                             slot, field.node, packed, cursor, matcher.action, matcher.action_index, writes.len(), matcher.tile_mask);
                    let visual_mask = self.sync_focus_visuals();
                    self.enqueue_render(RenderRequest::with_worklist(matcher.tile_mask | visual_mask,
                                        self.keyboard_packet_worklist_indices[slot]), "command-matcher");
                    return;
                }
                println!("command-matcher Enter rejected: slot={} field={} packed=0x{:016x} length={} state_writes=0 gpu_writes=0", slot, field.node, packed, cursor);
                let visual_mask = self.sync_focus_visuals();
                self.enqueue_render(RenderRequest::with_worklist(field.tile_mask | visual_mask,
                                    self.keyboard_packet_worklist_indices[slot]), "command-matcher-reject");
                return;
            }
        }
        match command.kind {
            KeyboardCommandKind::Action => {
                let action_index = command.action_index.expect("compiler command proof requires action_index");
                let action = self.action_slot_ids[action_index].clone();
                let writes = match self.action_write_plan_index(action_index) { Ok(writes) => writes, Err(error) => { eprintln!("keyboard-command action_index={action_index} ignored: {error:#}"); return; } };
                // apply_action_winner_writes remains the shared verified GPU executor; its lookup is eliminated in the next coalesced-task action-index patch.
                if let Err(error) = self.apply_action_winner_writes(&action, &writes) { eprintln!("keyboard-command action_index={action_index} ignored: {error:#}"); return; }
                println!("keyboard-command Enter: slot={} field={} action={} action_index={} winner_writes={} mask=0x{:016x}", slot, field.node, action, action_index, writes.len(), command.tile_mask);
            }
            KeyboardCommandKind::CommitPendingRegister => {
                let state_index = command.target_state_index.expect("compiler commit proof requires target state index");
                let committed_value = if field.charset == "ascii-upper" {
                    self.keyboard_text_values[slot] as i64
                } else {
                    i64::from(self.keyboard_pending_values[slot])
                };
                let state_id = self.state_slot_ids[state_index].clone();
                let previous_value = self.state_slot_values[state_index];
                self.state_slot_values[state_index] = committed_value;
                println!("keyboard-command Enter: slot={} field={} kind=commit-pending-register charset={} state={} state_index={} committed={}->{} mask=0x{:016x}",
                         slot, field.node, field.charset, state_id, state_index, previous_value, committed_value, command.tile_mask);
            }
            KeyboardCommandKind::CommitGroup => {
                let transaction_index = command.transaction_index.expect("compiler commit-group proof requires transaction_index");
                let transaction = self.compiled_transactions.get(transaction_index)
                    .expect("compiler command proof validated transaction index").clone();
                let keymap = self.keyboard.as_ref().expect("compiler transaction proof requires Keyboard Map");
                // Admission pass precedes every mutation: this is the atomic all-or-nothing boundary.
                let mut staged = Vec::with_capacity(transaction.field_slots.len());
                for (&field_slot, &state_index) in transaction.field_slots.iter().zip(transaction.state_indices.iter()) {
                    let group_field = keymap.fields.get(field_slot).expect("compiler transaction proof validated field slot");
                    let pending = self.keyboard_pending_values.get(field_slot).copied()
                        .expect("compiler transaction proof validated pending slot");
                    let group_digit_register = group_field.digit_register.as_ref()
                        .expect("compiler group transaction currently requires digit fields");
                    if pending > group_digit_register.maximum_value || state_index >= self.state_slot_values.len() {
                        println!("keyboard-command Enter: slot={} field={} kind=commit-group id={} transaction_index={} rejected field_slot={} pending={} maximum={}",
                                 slot, field.node, transaction.id, transaction_index, field_slot, pending, group_digit_register.maximum_value);
                        return;
                    }
                    staged.push((field_slot, state_index, i64::from(pending)));
                }
                // Commit pass is a fixed compiler order; it allocates no text/state lookup structures.
                let mut evidence = Vec::with_capacity(staged.len());
                for (field_slot, state_index, value) in staged {
                    let previous = self.state_slot_values[state_index];
                    self.state_slot_values[state_index] = value;
                    evidence.push(format!("field_slot={field_slot}:state_index={state_index}:{previous}->{value}"));
                }
                println!("keyboard-command Enter: slot={} field={} kind=commit-group id={} transaction_index={} atomic=true commits=[{}] mask=0x{:016x}",
                         slot, field.node, transaction.id, transaction_index, evidence.join(", "), command.tile_mask);
            }
            KeyboardCommandKind::Reset => {
                let (before, reset, clear_glyph) = if field.charset == "ascii-upper" {
                    let register = field.ascii_text_register.as_ref().expect("compiler ASCII proof requires text descriptor");
                    let before = self.keyboard_text_values[slot];
                    self.keyboard_text_values[slot] = register.reset_packed;
                    (format!("0x{before:016x}"), format!("0x{:016x}", register.reset_packed), 1u32 << 16)
                } else {
                    let register = field.digit_register.as_ref().expect("compiler digit proof requires descriptor");
                    let before = self.keyboard_pending_values[slot];
                    self.keyboard_pending_values[slot] = register.reset_value;
                    (before.to_string(), register.reset_value.to_string(), 0u32)
                };
                for offset in &field.glyph_id_offsets { self.queue.write_buffer(&self.glyph_buffer, *offset, bytemuck::bytes_of(&clear_glyph)); }
                self.keyboard_cursors[slot] = 0;
                println!("keyboard-command Escape: slot={} field={} charset={} reset_glyph_offsets={:?} mask=0x{:016x} pending={}->{}",
                         slot, field.node, field.charset, field.glyph_id_offsets, command.tile_mask, before, reset);
            }
        }
        let visual_mask = self.sync_focus_visuals();
        let worklist_index = match command.kind {
            KeyboardCommandKind::CommitGroup => self.transaction_packet_worklist_indices[
                command.transaction_index.expect("compiler commit-group proof requires transaction index")],
            KeyboardCommandKind::Action => RenderRequest::NO_PACKETS,
            KeyboardCommandKind::CommitPendingRegister | KeyboardCommandKind::Reset =>
                self.keyboard_packet_worklist_indices[slot],
        };
        self.enqueue_render(RenderRequest::with_worklist(command.tile_mask | visual_mask, worklist_index),
                            "keyboard-command");
    }

    fn execute_pointer_transaction(&mut self, event_slot: usize, transaction_index: usize, operation: &str) {
        let transaction = match self.compiled_transactions.get(transaction_index) {
            Some(plan) => plan.clone(),
            None => { eprintln!("pointer transaction ignored: index={transaction_index} outside compiler table"); return; }
        };
        let event_node = self.scene.event_map[event_slot].node.clone();
        let keymap = match self.keyboard.as_ref() { Some(map) => map, None => { eprintln!("pointer transaction ignored: no keyboard map"); return; } };
        match operation {
            "commit" => {
                let mut staged = Vec::with_capacity(transaction.field_slots.len());
                for (&field_slot, &state_index) in transaction.field_slots.iter().zip(transaction.state_indices.iter()) {
                    let field = &keymap.fields[field_slot];
                    let pending = self.keyboard_pending_values[field_slot];
                    let digit_register = field.digit_register.as_ref()
                        .expect("compiler pointer group transaction currently requires digit fields");
                    if pending > digit_register.maximum_value || state_index >= self.state_slot_values.len() {
                        println!("pointer-transaction: node={} operation=commit id={} index={} rejected field_slot={} pending={} maximum={}",
                                 event_node, transaction.id, transaction_index, field_slot, pending, digit_register.maximum_value);
                        return;
                    }
                    staged.push((field_slot, state_index, i64::from(pending)));
                }
                let mut evidence = Vec::with_capacity(staged.len());
                for (field_slot, state_index, value) in staged {
                    let previous = self.state_slot_values[state_index];
                    self.state_slot_values[state_index] = value;
                    evidence.push(format!("field_slot={field_slot}:state_index={state_index}:{previous}->{value}"));
                }
                println!("pointer-transaction: node={} operation=commit id={} index={} atomic=true commits=[{}] mask=0x{:016x}",
                         event_node, transaction.id, transaction_index, evidence.join(", "), transaction.tile_mask);
            }
            "reset" => {
                let mut evidence = Vec::with_capacity(transaction.field_slots.len());
                for &field_slot in &transaction.field_slots {
                    let field = &keymap.fields[field_slot];
                    let before = self.keyboard_pending_values[field_slot];
                    let digit_register = field.digit_register.as_ref()
                        .expect("compiler pointer group transaction currently requires digit fields");
                    for offset in &field.glyph_id_offsets { self.queue.write_buffer(&self.glyph_buffer, *offset, bytemuck::bytes_of(&0u32)); }
                    self.keyboard_cursors[field_slot] = 0;
                    self.keyboard_pending_values[field_slot] = digit_register.reset_value;
                    evidence.push(format!("field_slot={field_slot}:{before}->{}", digit_register.reset_value));
                }
                println!("pointer-transaction: node={} operation=reset id={} index={} state_writes=0 resets=[{}] mask=0x{:016x}",
                         event_node, transaction.id, transaction_index, evidence.join(", "), transaction.tile_mask);
            }
            _ => { eprintln!("pointer transaction ignored: unsupported operation {operation}"); return; }
        }
        let visual_mask = self.sync_focus_visuals();
        self.enqueue_render(RenderRequest::with_worklist(transaction.tile_mask | visual_mask,
                            self.transaction_packet_worklist_indices[transaction_index]), "pointer-transaction");
    }

    fn set_hover(&mut self, next: Option<usize>) {
        if self.hovered == next { return; }
        let mut mask = 0u64;
        if let Some(old) = self.hovered {
            let c = self.scene.event_map[old].base_color;
            self.patch_color(old, c);
            mask |= self.event_tile_masks[old].hover;
        }
        if let Some(new) = next {
            println!("event-map hover: slot {} / {}", self.scene.event_map[new].slot, self.scene.event_map[new].node);
            let c = self.scene.event_map[new].hover_color;
            self.patch_color(new, c);
            mask |= self.event_tile_masks[new].hover;
        }
        self.hovered = next;
        self.mark_dirty_tiles(mask, "hover");
    }

    fn pointer_down(&mut self) {
        if let Some(index) = self.hit_test(self.cursor) {
            self.pressed = Some(index);
            let batch_id = self.event_batch_ids[index].press.clone();
            self.execute_coalesced_batch(&batch_id);
        }
    }

    fn pointer_up(&mut self) {
        if let Some(index) = self.pressed.take() {
            if self.hit_test(self.cursor) == Some(index) {
                let transaction = self.scene.event_map[index].transaction_index
                    .zip(self.scene.event_map[index].transaction_op.clone());
                if let Some((transaction_index, operation)) = transaction {
                    // Activate batch仍按 compiler-tagged release → transaction task-ref 顺序执行；
                    // Transaction ref 的业务 mutation 随后由同一 fixed index 的 pointer executor 完成。
                    let batch_id = self.event_batch_ids[index].activate.clone();
                    self.dispatch_compiler_batch(&batch_id);
                    self.execute_pointer_transaction(index, transaction_index, &operation);
                    self.apply_overlay_state(index);
                } else {
                    let batch_id = self.event_batch_ids[index].activate.clone();
                    self.dispatch_compiler_batch(&batch_id);
                    self.apply_navigation_selection(index);
                    self.apply_overlay_state(index);
                }
            } else {
                // 取消点击仍必须恢复 button。该路径没有 action，直接执行 compiler release task。
                let release_id = self.event_batch_ids[index].release.clone();
                self.execute_release_task(&release_id);
            }
        }
    }

    fn apply_overlay_state(&mut self, event_slot: usize) -> bool {
        let Some(plan) = self.overlay_state_plan.clone() else { return false; };
        let action = match self.scene.event_map.get(event_slot).and_then(|event| event._action.as_deref()) {
            Some(action) => action.to_string(),
            None => return false,
        };
        let Some(entry) = plan.entries.iter().find(|entry| entry.event_slots.contains(&event_slot)
            && (entry.open_action == action || entry.close_actions.iter().any(|candidate| candidate == &action))) else { return false; };
        let visible = entry.open_action == action;
        if self.state_slot_values.get(entry.state_index).copied() != Some(i64::from(visible)) {
            eprintln!("overlay-state rejected: {} state slot {} did not receive {}", entry.id, entry.state_index, i64::from(visible));
            return false;
        }
        for (&offset, &base_alpha) in entry.instance_offsets.iter().zip(entry.instance_alphas.iter()) {
            self.patch_instance_f32((offset + 28) as u64, if visible { base_alpha } else { 0.0 });
        }
        for &slot in &entry.glyph_slots { self.patch_placement_alpha(slot, if visible { 1.0 } else { 0.0 }); }
        for &shadow_index in &entry.shadow_indices {
            let alpha = if visible { self.shadow_instances[shadow_index].color[3].max(0.0) } else { 0.0 };
            // Original recipe alpha is restored from the immutable compiler source plan.
            let base_alpha = self.scene.shadow_surface_plan.as_ref().expect("overlay shadow plan admitted").layers[shadow_index].opacity;
            let value = if visible { base_alpha } else { alpha };
            self.shadow_instances[shadow_index].color[3] = value;
            self.queue.write_buffer(&self.shadow_instance_buffer, (shadow_index * std::mem::size_of::<QuadInstance>() + 28) as u64, bytemuck::bytes_of(&value));
        }
        self.enqueue_render(RenderRequest::no_packets(entry.tile_mask), "overlay-state");
        self.modal_focus_overlay_transition(&entry.id, visible);
        println!("overlay-state: id={} action={} visible={} quad-alpha-patches={} glyph-alpha-patches={} tile-mask=0x{:016x} worklist=no-packets",
                 entry.id, action, visible, entry.instance_offsets.len(), entry.glyph_slots.len(), entry.tile_mask);
        true
    }

    fn modal_focus_overlay_transition(&mut self, overlay_id: &str, visible: bool) {
        let transition = {
            let Some(plan) = self.modal_focus_subgraph_plan.as_mut() else { return; };
            let Some(entry) = plan.entries.iter_mut().find(|entry| entry.id == overlay_id) else { return; };
            if visible {
                entry.current_index = 0;
                (entry.id.clone(), Some(entry.focus_event_slots[entry.current_index]), entry.restore_event_slot, entry.tile_mask)
            } else {
                (entry.id.clone(), None, entry.restore_event_slot, entry.tile_mask)
            }
        };
        let (id, focus_event_slot, restore_event_slot, tile_mask) = transition;
        if let Some(slot) = focus_event_slot {
            let ring_index = self.set_focus_ring_for_event(slot, 1.0);
            println!("modal-focus: overlay={} transition=open focus-event-slot={} focus-ring={:?} alpha-patches=1 tile-mask=0x{:016x}",
                     id, slot, ring_index, tile_mask);
        } else {
            let cleared = self.clear_all_focus_rings();
            println!("modal-focus: overlay={} transition=close restore-event-slot={} focus-ring-alpha-clears={} background-isolated=false",
                     id, restore_event_slot, cleared);
        }
    }

    fn modal_focus_tab(&mut self, backward: bool) -> bool {
        let transition = {
            let Some(plan) = self.modal_focus_subgraph_plan.as_mut() else { return false; };
            let Some(entry) = plan.entries.iter_mut().find(|entry| self.state_slot_values.get(entry.state_index).copied() == Some(1)) else { return false; };
            let current_slot = entry.focus_event_slots[entry.current_index];
            let next_slot = if backward { entry.previous_slots[entry.current_index] } else { entry.next_slots[entry.current_index] };
            let next_index = entry.focus_event_slots.iter().position(|slot| *slot == next_slot)
                .expect("compiler modal focus ring has admitted next slot");
            entry.current_index = next_index;
            (entry.id.clone(), current_slot, next_slot, entry.allowed_event_slots.clone(), entry.tile_mask)
        };
        let (id, current_slot, next_slot, allowed_event_slots, tile_mask) = transition;
        let old_ring = self.set_focus_ring_for_event(current_slot, 0.0)
            .expect("admitted modal focus target has a preallocated focus ring");
        let new_ring = self.set_focus_ring_for_event(next_slot, 1.0)
            .expect("admitted modal focus target has a preallocated focus ring");
        self.enqueue_render(RenderRequest::no_packets(tile_mask), "modal-focus-ring-tab");
        println!("modal-focus: overlay={} key={} from-event-slot={} to-event-slot={} rings={}=>{} alpha-patches=2 allowed={:?} tile-mask=0x{:016x}",
                 id, if backward { "shift-tab" } else { "tab" }, current_slot, next_slot,
                 old_ring, new_ring, allowed_event_slots, tile_mask);
        true
    }

    fn modal_focus_activate(&mut self) -> bool {
        let Some(plan) = self.modal_focus_subgraph_plan.clone() else { return false; };
        let Some(entry) = plan.entries.iter().find(|entry| self.state_slot_values.get(entry.state_index).copied() == Some(1)) else { return false; };
        let event_slot = entry.focus_event_slots[entry.current_index];
        assert!(entry.allowed_event_slots.contains(&event_slot),
                "compiler-admitted modal focus current event slot escaped fixed allowed set");
        let batch_id = self.event_batch_ids[event_slot].activate.clone();
        self.dispatch_compiler_batch(&batch_id);
        let closed = self.apply_overlay_state(event_slot);
        println!("modal-focus: overlay={} key=enter event-slot={} close-transition={}", entry.id, event_slot, closed);
        true
    }

    fn dismiss_active_overlay_with_escape(&mut self) -> bool {
        let Some(plan) = self.overlay_state_plan.clone() else { return false; };
        let Some(entry) = plan.entries.iter().find(|entry| self.state_slot_values.get(entry.state_index).copied() == Some(1)) else { return false; };
        let Some(&event_slot) = entry.event_slots.iter().find(|&&slot| {
            self.scene.event_map.get(slot).and_then(|event| event._action.as_deref())
                .map(|action| entry.close_actions.iter().any(|candidate| candidate == action)).unwrap_or(false)
        }) else { return false; };
        let batch_id = self.event_batch_ids[event_slot].activate.clone();
        self.dispatch_compiler_batch(&batch_id);
        self.apply_overlay_state(event_slot)
    }

    fn apply_material_observability_workbench_view_selection(&mut self, previous_index: usize, next_index: usize) -> u64 {
        let Some(plan_snapshot) = self.material_observability_workbench_plan.clone() else { return 0; };
        if plan_snapshot.selected_index == next_index { return 0; }
        let previous = plan_snapshot.views.get(previous_index)
            .expect("navigation-selected workbench previous view is compiler admitted");
        let next = plan_snapshot.views.get(next_index)
            .expect("navigation-selected workbench next view is compiler admitted");
        for &offset in &previous.instance_offsets { self.patch_instance_f32((offset + 28) as u64, 0.0); }
        for &slot in &previous.glyph_slots { self.patch_placement_alpha(slot, 0.0); }
        for &shadow_index in &previous.shadow_indices {
            self.shadow_instances[shadow_index].color[3] = 0.0;
            self.queue.write_buffer(&self.shadow_instance_buffer, (shadow_index * std::mem::size_of::<QuadInstance>() + 28) as u64, bytemuck::bytes_of(&0.0f32));
        }
        for (&offset, &alpha) in next.instance_offsets.iter().zip(next.instance_alphas.iter()) {
            self.patch_instance_f32((offset + 28) as u64, alpha);
        }
        for &slot in &next.glyph_slots { self.patch_placement_alpha(slot, 1.0); }
        for (&shadow_index, &alpha) in next.shadow_indices.iter().zip(next.shadow_alphas.iter()) {
            self.shadow_instances[shadow_index].color[3] = alpha;
            self.queue.write_buffer(&self.shadow_instance_buffer, (shadow_index * std::mem::size_of::<QuadInstance>() + 28) as u64, bytemuck::bytes_of(&alpha));
        }
        let mask = previous.tile_mask | next.tile_mask;
        let instance_patches = previous.instance_offsets.len() + next.instance_offsets.len();
        let glyph_patches = previous.glyph_slots.len() + next.glyph_slots.len();
        let shadow_patches = previous.shadow_indices.len() + next.shadow_indices.len();
        self.material_observability_workbench_plan.as_mut()
            .expect("cloned workbench plan remains resident").selected_index = next_index;
        println!("material-workbench view-switch: old={} new={} instance-alpha-patches={} glyph-alpha-patches={} shadow-alpha-patches={} tile-mask=0x{:016x}",
                 previous.destination_id, next.destination_id, instance_patches, glyph_patches, shadow_patches, mask);
        mask
    }

    fn apply_navigation_selection(&mut self, event_slot: usize) -> bool {
        let Some(plan_snapshot) = self.navigation_selection_plan.clone() else { return false; };
        let Some(next_index) = plan_snapshot.destinations.iter().position(|destination| destination.event_slot == event_slot) else { return false; };
        let previous_index = plan_snapshot.selected_index;
        if previous_index == next_index {
            println!("navigation-selection: rail={} destination={} unchanged=true state-slot={} target={}",
                     plan_snapshot.rail_id, plan_snapshot.destinations[next_index].id,
                     plan_snapshot.state_index, plan_snapshot.destinations[next_index].target_value);
            return true;
        }
        let next = &plan_snapshot.destinations[next_index];
        if self.state_slot_values.get(plan_snapshot.state_index).copied() != Some(next.target_value) {
            eprintln!("navigation-selection rejected: state slot {} did not receive target {}", plan_snapshot.state_index, next.target_value);
            return false;
        }
        let previous = &plan_snapshot.destinations[previous_index];
        for (destination, color) in [(previous, previous.unselected_color), (next, next.selected_color)] {
            let slot = destination.instance_offset / std::mem::size_of::<QuadInstance>();
            self.instances[slot].color = color;
            self.queue.write_buffer(&self.instance_buffer, (destination.instance_offset + 16) as u64, bytemuck::cast_slice(&color));
        }
        let workbench_mask = self.apply_material_observability_workbench_view_selection(previous_index, next_index);
        let selection_mask = previous.tile_mask | next.tile_mask | workbench_mask;
        if let Some(request) = self.pending_render.last_mut() {
            if request.packet_worklist_index == RenderRequest::NO_PACKETS && request.scroll_list_index.is_none() {
                request.tile_mask |= selection_mask;
                println!("navigation-selection render-coalesce: mask=0x{:016x} worklist=no-packets", request.tile_mask);
            } else {
                self.enqueue_render(RenderRequest::no_packets(selection_mask), "navigation-selection");
            }
        } else {
            self.enqueue_render(RenderRequest::no_packets(selection_mask), "navigation-selection");
        }
        self.navigation_selection_plan.as_mut().expect("cloned navigation selection remains resident").selected_index = next_index;
        println!("navigation-selection: rail={} old={} new={} state-slot={} target={} color-patches=2 workbench-mask=0x{:016x} tile-mask=0x{:016x} worklist=no-packets",
                 plan_snapshot.rail_id, previous.id, next.id, plan_snapshot.state_index, next.target_value, workbench_mask, selection_mask);
        true
    }

    fn apply_transient_winner_write(&mut self, task_id: &str, offset: usize, byte_length: usize) -> Result<()> {
        let event_slot = *self.frame_task_event_slots.get(task_id)
            .with_context(|| format!("winner task {task_id} has no compiler Event Map slot"))?;
        let (pos_offset, color_offset, pressed_pos, pressed_color, base_pos, hover_color) = {
            let event = &self.scene.event_map[event_slot];
            (event.instance_offset, event.instance_offset + 16, event.pressed_pos, event.pressed_color, event.base_pos, event.hover_color)
        };
        if task_id.starts_with("release-") {
            anyhow::ensure!((offset == pos_offset && byte_length == 8) || (offset == color_offset && byte_length == 16),
                            "release winner task {task_id} write [{offset}..{}) does not match its fixed visual field", offset + byte_length);
            // The compiler emits the position write before its color write. Start exactly once
            // on color ownership, so all visual fields remain in the pressed endpoint until tick.
            if offset == color_offset { self.start_release_motion(event_slot); }
            println!("coalesced-winner transient {task_id}: [{offset}..{}) motion=scheduled", offset + byte_length);
            return Ok(());
        }
        let (pos, color) = if task_id.starts_with("pressed-") {
            (pressed_pos, pressed_color)
        } else if task_id.starts_with("hover-") {
            (base_pos, hover_color)
        } else {
            anyhow::bail!("non-action winner task {task_id} has unsupported compiler kind")
        };
        if offset == pos_offset && byte_length == 8 {
            self.instances[pos_offset / 44].pos = pos;
            self.queue.write_buffer(&self.instance_buffer, offset as u64, bytemuck::cast_slice(&pos));
        } else if offset == color_offset && byte_length == 16 {
            self.instances[pos_offset / 44].color = color;
            self.queue.write_buffer(&self.instance_buffer, offset as u64, bytemuck::cast_slice(&color));
        } else {
            anyhow::bail!("winner task {task_id} write [{offset}..{}) does not match its fixed visual field", offset + byte_length)
        }
        println!("coalesced-winner transient {task_id}: [{offset}..{})", offset + byte_length);
        Ok(())
    }

    fn start_release_motion(&mut self, event_slot: usize) {
        let Some(track_index) = self.release_tracks.iter().position(|track| track.event_slot == event_slot) else {
            eprintln!("release motion ignored: event slot {event_slot} has no compiler track");
            return;
        };
        self.active_release_tracks.retain(|active| self.release_tracks[active.track_index].event_slot != event_slot);
        let track = &self.release_tracks[track_index];
        self.active_release_tracks.push(ActiveReleaseTrack { track_index, started_at: Instant::now() });
        println!("release-motion start: id={} event-slot={} duration-ms={} tile-mask=0x{:016x}",
                 track.id, event_slot, track.duration_ms, track.tile_mask);
    }

    fn tick_release_motion(&mut self) -> bool {
        if self.active_release_tracks.is_empty() { return false; }
        let now = Instant::now();
        let active = std::mem::take(&mut self.active_release_tracks);
        let mut continuing = Vec::with_capacity(active.len());
        let mut dirty_mask = 0u64;
        for active_track in active {
            let track = self.release_tracks[active_track.track_index].clone();
            let elapsed_ms = now.duration_since(active_track.started_at).as_secs_f32() * 1000.0;
            let linear = (elapsed_ms / track.duration_ms as f32).clamp(0.0, 1.0);
            // v1 admits exactly the compiler-selected ease-out quadratic; no runtime curve dispatch.
            let t = 1.0 - (1.0 - linear) * (1.0 - linear);
            let pos = [
                track.pos_from[0] + (track.pos_to[0] - track.pos_from[0]) * t,
                track.pos_from[1] + (track.pos_to[1] - track.pos_from[1]) * t,
            ];
            let color = [
                track.color_from[0] + (track.color_to[0] - track.color_from[0]) * t,
                track.color_from[1] + (track.color_to[1] - track.color_from[1]) * t,
                track.color_from[2] + (track.color_to[2] - track.color_from[2]) * t,
                track.color_from[3] + (track.color_to[3] - track.color_from[3]) * t,
            ];
            let slot = track.instance_offset / std::mem::size_of::<QuadInstance>();
            self.instances[slot].pos = pos;
            self.instances[slot].color = color;
            self.queue.write_buffer(&self.instance_buffer, track.pos_offset as u64, bytemuck::cast_slice(&pos));
            self.queue.write_buffer(&self.instance_buffer, track.color_offset as u64, bytemuck::cast_slice(&color));
            dirty_mask |= track.tile_mask;
            if linear < 1.0 {
                continuing.push(active_track);
            } else {
                println!("release-motion complete: id={} event-slot={} frames=bounded", track.id, track.event_slot);
            }
        }
        self.active_release_tracks = continuing;
        if dirty_mask != 0 { self.mark_dirty_tiles(dirty_mask, "release-motion"); }
        !self.active_release_tracks.is_empty()
    }

    fn apply_action_winner_writes(&mut self, action_id: &str, writes: &[FrameCoalescedWrite]) -> Result<()> {
        let action = self.scene.actions.get(action_id).cloned()
            .with_context(|| format!("coalesced batch references unknown action {action_id}"))?;
        println!("event-map dispatch: {action_id}");
        for state_write in &action.writes {
            let slot = self.state_slot_values.get_mut(state_write.state_index)
                .expect("compiler state-slot proof validated action write index");
            match state_write.op.as_str() {
                "add" => *slot += state_write.value,
                "set" => *slot = state_write.value,
                other => { eprintln!("unsupported compiler state write operation {other} for action {action_id}"); return Err(anyhow::anyhow!("unsupported action state write")); }
            }
            println!("state-slot write: action={} state={} index={} op={} value={}",
                     action_id, state_write.state, state_write.state_index, state_write.op, *slot);
        }
        for update in &action.gpu_updates {
            if update.kind != "text-run" { continue; }
            let value = self.state_slot_values[update.state_index];
            let glyph_ids = digit_ids(value, update.glyph_count)
                .map_err(|_| anyhow::anyhow!("compiler action {action_id} has invalid fixed digit plan"))?;
            let offsets: Vec<usize> = if update.glyph_id_offsets.is_empty() {
                (0..update.glyph_count).map(|index| update.offset + index * GLYPH_CELL_BYTES).collect()
            } else { update.glyph_id_offsets.clone() };
            anyhow::ensure!(offsets.len() == glyph_ids.len(), "compiler action {action_id} glyph offset count mismatch");
            anyhow::ensure!(offsets.iter().all(|offset| *offset >= update.offset && *offset + 4 <= update.offset + update.byte_length),
                            "compiler action {action_id} glyph ID offset escapes its fixed update range");
            let mut patched = Vec::new();
            for (offset, glyph_id) in offsets.iter().zip(glyph_ids.iter()) {
                if writes.iter().any(|write| write.task_id == action_id && write.offset == *offset && write.byte_length == 4) {
                    self.queue.write_buffer(&self.glyph_buffer, *offset as u64, &glyph_id.to_le_bytes());
                    patched.push(*offset);
                }
            }
            anyhow::ensure!(patched.len() == offsets.len(), "coalesced action {action_id} omitted a required glyph ID winner write");
            let ranges = patched.iter().map(|offset| format!("[{offset}..{})", offset + 4)).collect::<Vec<_>>().join(", ");
            println!("glyph-id-patch {}: {ranges} ({} bytes)", update.node, patched.len() * 4);
        }
        for update in &action.instance_updates {
            anyhow::ensure!(writes.iter().any(|write| write.task_id == action_id && write.offset == update.offset && write.byte_length == update.byte_length), "coalesced action {action_id} omitted required instance winner write");
            anyhow::ensure!(update.field == "size.x" && update.byte_length == 4, "unsupported compiler instance update {}.{}", update.node, update.field);
            let value = self.state_slot_values.get(update.state_index)
                .copied().with_context(|| format!("instance update {} has invalid compiler state_index {}", update.node, update.state_index))? as f32 * update.scale;
            self.queue.write_buffer(&self.instance_buffer, update.offset as u64, bytemuck::bytes_of(&value));
            self.instances[update.offset / 44].size[0] = value;
            println!("instance-patch {} state={} state_index={}: [{}..{}) size.x={value:.6}", update.node, update.state, update.state_index, update.offset, update.offset + update.byte_length);
        }
        Ok(())
    }

    fn apply_compiler_batch_writes(&mut self, batch_id: &str) -> Option<(CompiledBatch, usize)> {
        let Some(batch) = self.coalesced_batches.get(batch_id).cloned() else {
            eprintln!("compiler coalesced batch {batch_id} missing"); return None;
        };
        println!("coalesced-batch execute: {} refs={:?} worklist_slots={:?}", batch.id, batch.execution_refs, batch.task_worklist_indices);
        for (task_ref, worklist_index) in batch.execution_refs.iter().zip(batch.task_worklist_indices.iter()) {
            println!("coalesced-batch task-worklist-slot: task={task_ref:?} index={worklist_index}");
            match *task_ref {
                CompiledTaskRef::Action(action_index) => {
                    let task_id = self.action_slot_ids.get(action_index).expect("compiler batch proof validated action slot").clone();
                    let task_writes: Vec<FrameCoalescedWrite> = batch.winner_writes.iter()
                        .filter(|write| write.task_id == task_id).cloned().collect();
                    if let Err(error) = self.apply_action_winner_writes(&task_id, &task_writes) { eprintln!("coalesced action_index={action_index} ignored: {error}"); return None; }
                }
                CompiledTaskRef::Transaction(transaction_index) => {
                    // The transaction's business mutation is performed by the pointer dispatcher after visual release.
                    // This batch branch only preserves compiler-ordered task-ref evidence and has no winner GPU range.
                    println!("coalesced-batch transaction-ref: index={transaction_index} deferred-to-pointer-dispatch");
                }
                CompiledTaskRef::Transient(transient_index) => {
                    let task_id = self.transient_task_ids.get(transient_index).expect("compiler batch proof validated transient slot").clone();
                    let task_writes: Vec<FrameCoalescedWrite> = batch.winner_writes.iter()
                        .filter(|write| write.task_id == task_id).cloned().collect();
                    for write in &task_writes {
                        if let Err(error) = self.apply_transient_winner_write(&task_id, write.offset, write.byte_length) { eprintln!("coalesced transient_index={transient_index} ignored: {error}"); return None; }
                    }
                }
            }
        }
        println!("coalesced-batch composite-worklist: batch={} slot={} members={:?} packets={:?}",
                 batch.id, batch.composite_worklist_index, batch.composite_worklist_member_indices,
                 batch.composite_worklist_packet_indices);
        Some((batch.clone(), batch.composite_worklist_index))
    }

    // Replay/legacy path explicitly requires the coalesced tile executor; it never makes a cost decision.
    fn execute_coalesced_batch(&mut self, batch_id: &str) {
        if let Some((batch, worklist_index)) = self.apply_compiler_batch_writes(batch_id) {
            self.enqueue_render(RenderRequest::with_worklist(batch.tile_mask, worklist_index), &batch.id);
        }
    }

    // Pointer-up activate path: strategy was fixed by the Racket compiler and verified once at startup.
    fn dispatch_compiler_batch(&mut self, batch_id: &str) {
        let Some((batch, worklist_index)) = self.apply_compiler_batch_writes(batch_id) else { return; };
        println!("compiler strategy dispatch: batch={} strategy={} worklist={}", batch.id, batch.strategy.id(), worklist_index);
        let request = match batch.strategy {
            CompilerStrategy::Coalesced => RenderRequest::with_strategy(batch.tile_mask, batch.strategy, worklist_index),
            CompilerStrategy::FullRedraw => RenderRequest::with_strategy(self.all_schedule_tile_mask(), batch.strategy, RenderRequest::ALL_PACKETS),
            CompilerStrategy::PacketAware => RenderRequest::with_strategy(self.all_schedule_tile_mask(), batch.strategy, worklist_index),
        };
        self.enqueue_render(request, &batch.id);
    }

    fn execute_release_task(&mut self, task_id: &str) {
        let Some(&event_slot) = self.frame_task_event_slots.get(task_id) else { return; };
        self.start_release_motion(event_slot);
    }

    fn bind_glyph_placement_pipeline<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>) {
        pass.set_pipeline(&self.text_pipeline);
        pass.set_vertex_buffer(0, self.unit_quad.slice(..));
        pass.set_vertex_buffer(1, self.placement_buffer.slice(..));
        pass.set_bind_group(0, &self.glyph_bind_group, &[]);
    }

    // 仅用于初始/显式整屏路径；局部 scissor tile 永远调用 draw_tile_glyph_packets。
    fn draw_all_glyph_packets<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>) {
        self.bind_glyph_placement_pipeline(pass);
        if let Some(activity) = &self.packet_activity {
            for packet in &self.subgroup_packets {
                let atlas_page = self.scene.glyph_draw_packets[packet.packet_index].atlas_page;
                // font_placement_plan v1 is deliberately static and sparse (title/header/detail
                // chrome). Dozen/llvmpipe may drop later indirect commands in a multi-command
                // page-2 pass although command readback is correct, so its compiler-known
                // subrange uses direct draw. Legacy/dynamic packets retain compute worklist ->
                // indirect draw when the adapter exposes vertex subgroup support; otherwise the
                // same compiler-proved ranges use this compatible direct executor.
                if atlas_page == 2 || !self.subgroup_vertex_supported {
                    let reason = if atlas_page == 2 { "page2-static-v1" } else { "no-vertex-subgroup-compatible-direct" };
                    println!("glyph-direct-draw full packet={} page={} placements=[{}..{}) lanes={} reason={}", packet.packet_index, atlas_page, packet.first_placement, packet.first_placement + packet.lane_count, packet.lane_count, reason);
                    pass.draw(0..6, packet.first_placement..packet.first_placement + packet.lane_count);
                } else {
                    println!("packet-indirect-draw full packet={} activity_word={} indirect_offset={} lanes={} dynamic={}", packet.packet_index, packet.activity_word_offset, packet.indirect_byte_offset, packet.lane_count, packet.dynamic);
                    pass.draw_indirect(&activity.indirect_buffer, packet.indirect_byte_offset);
                }
            }
            return;
        }
        if self.subgroup_packets.is_empty() {
            for packet in &self.scene.glyph_draw_packets {
                pass.draw(0..6, packet.first_placement..packet.first_placement + packet.placement_count);
            }
            return;
        }
        for packet in &self.subgroup_packets {
            println!("subgroup-packet-draw full packet={} placements=[{}..{}) lanes={} active_mask=0x{:08x} dynamic={} vertex_subgroup={}",
                     packet.packet_index, packet.first_placement, packet.first_placement + packet.lane_count,
                     packet.lane_count, packet.active_lane_mask, packet.dynamic, self.subgroup_vertex_supported);
            pass.draw(0..6, packet.first_placement..packet.first_placement + packet.lane_count);
        }
    }

    // `ranges` 已由 Racket compiler 完整裁剪与验证。此处仅绑定 Placement Buffer 并执行
    // 固定 instance range draw；不做 UI tree 遍历、bounds 计算或 packet/tile 相交测试。
    // A compiler `no-packets` worklist means packet activity compute is intentionally absent.
    // Dynamic glyph bytes may still have changed inside compiler-proved placement ranges; draw
    // those ranges directly rather than consuming a stale zero-activity indirect command.
    fn draw_tile_glyph_packets<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>, tile_index: usize, ranges: &'a [GlyphPacketRange], direct_for_no_packets: bool) {
        if ranges.is_empty() { return; }
        self.bind_glyph_placement_pipeline(pass);
        for range in ranges {
            let packet = &self.scene.glyph_draw_packets[range.packet_index];
            let end = range.first_placement + range.placement_count;
            if self.subgroup_packets.is_empty() {
                println!("tile-glyph-draw tile={tile_index} packet={} page={} placements=[{}..{}) count={} dynamic={}", range.packet_index, packet.atlas_page, range.first_placement, end, range.placement_count, range.dynamic);
                pass.draw(0..6, range.first_placement..end);
            } else {
                for subgroup in self.subgroup_packets.iter().filter(|subgroup| subgroup.packet_index == range.packet_index) {
                    let subgroup_end = subgroup.first_placement + subgroup.lane_count;
                    let start = range.first_placement.max(subgroup.first_placement);
                    let clipped_end = end.min(subgroup_end);
                    if start >= clipped_end { continue; }
                    if let Some(activity) = &self.packet_activity {
                        if packet.atlas_page == 2 || !self.subgroup_vertex_supported {
                            let reason = if packet.atlas_page == 2 { "page2-static-v1" } else { "no-vertex-subgroup-compatible-direct" };
                            println!("glyph-direct-draw tile={} packet={} page={} placements=[{}..{}) lanes={} reason={}",
                                     tile_index, subgroup.packet_index, packet.atlas_page, start, clipped_end, subgroup.lane_count, reason);
                            pass.draw(0..6, start..clipped_end);
                        } else if !direct_for_no_packets && start == subgroup.first_placement && clipped_end == subgroup_end {
                            println!("packet-indirect-draw tile={} packet={} page={} activity_word={} indirect_offset={} lanes={} dynamic={}",
                                     tile_index, subgroup.packet_index, packet.atlas_page, subgroup.activity_word_offset,
                                     subgroup.indirect_byte_offset, subgroup.lane_count, subgroup.dynamic);
                            pass.draw_indirect(&activity.indirect_buffer, subgroup.indirect_byte_offset);
                        } else {
                            let reason = if direct_for_no_packets { "no-packets-direct" } else { "tile-clipped" };
                            println!("packet-direct-subrange tile={} packet={} page={} placements=[{}..{}) lanes={} reason={}", tile_index, subgroup.packet_index, packet.atlas_page, start, clipped_end, subgroup.lane_count, reason);
                            pass.draw(0..6, start..clipped_end);
                        }
                    } else {
                        println!("subgroup-packet-draw tile={} packet={} page={} placements=[{}..{}) lanes={} active_mask=0x{:08x} dynamic={} vertex_subgroup={}",
                                 tile_index, subgroup.packet_index, packet.atlas_page, start, clipped_end,
                                 subgroup.lane_count, subgroup.active_lane_mask, subgroup.dynamic, self.subgroup_vertex_supported);
                        pass.draw(0..6, start..clipped_end);
                    }
                }
            }
        }
    }

    // virtual-list row glyph ranges are compiler-proved contiguous placement spans.
    // Scroll submission uses these spans directly: no packet scan, node lookup, or range clipping.
    fn draw_virtual_row_glyph_subranges<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>, ranges: &'a [VirtualRowSubrange]) {
        if ranges.is_empty() { return; }
        self.bind_glyph_placement_pipeline(pass);
        for range in ranges {
            pass.draw(0..6, range.first..range.first + range.count);
        }
    }

    fn draw_ranges<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>, ranges: impl Iterator<Item=&'a DrawRange>) {
        pass.set_vertex_buffer(0, self.unit_quad.slice(..));
        pass.set_vertex_buffer(1, self.instance_buffer.slice(..));
        pass.set_pipeline(&self.static_pipeline);
        pass.set_bind_group(0, &self.rounded_surface_bind_group, &[]);
        for range in ranges { pass.draw(0..6, range.first_instance..range.first_instance + range.instance_count); }
    }

    fn reset_replay_state(&mut self) {
        self.pending_render.clear();
        self.state_slot_values.clone_from(&self.initial_state_slot_values);
        self.instances.clone_from(&self.initial_instances);
        self.queue.write_buffer(&self.instance_buffer, 0, bytemuck::cast_slice(&self.instances));
        self.queue.write_buffer(&self.glyph_buffer, 0, &self.initial_glyph_bytes);
        self.clear_all_focus_rings();
        if let Some(plan) = self.modal_focus_subgraph_plan.as_mut() {
            for entry in &mut plan.entries { entry.current_index = 0; }
        }
        self.canvas_dirty = false;
    }

    fn summarize_samples(mut samples: Vec<f64>) -> SampleStatistics {
        samples.sort_by(|left, right| left.partial_cmp(right).unwrap());
        let count = samples.len();
        let p95_index = ((count as f64 * 0.95).ceil() as usize).saturating_sub(1);
        SampleStatistics {
            sample_count: count,
            min_ns: samples[0],
            median_ns: samples[(count - 1) / 2],
            p95_ns: samples[p95_index],
            max_ns: samples[count - 1],
            mean_ns: samples.iter().sum::<f64>() / count as f64,
        }
    }

    fn read_gpu_timestamp_ns(&self) -> Option<f64> {
        let timer = self.gpu_timer.as_ref()?;
        let slice = timer.readback_buffer.slice(..);
        let (sender, receiver) = mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| { let _ = sender.send(result); });
        if self.device.poll(wgpu::PollType::wait_indefinitely()).is_err() { return None; }
        receiver.recv().ok()?.ok()?;
        let mapped = match slice.get_mapped_range() { Ok(mapped) => mapped, Err(_) => { timer.readback_buffer.unmap(); return None; } };
        if mapped.len() != 16 { drop(mapped); timer.readback_buffer.unmap(); return None; }
        let values: &[u64] = bytemuck::cast_slice(&mapped);
        let elapsed = values[1].checked_sub(values[0]).map(|ticks| ticks as f64 * timer.timestamp_period_ns as f64);
        drop(mapped);
        timer.readback_buffer.unmap();
        elapsed
    }

    fn draw_shadow_surfaces<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>) {
        if self.shadow_instance_count == 0 { return; }
        pass.set_pipeline(&self.shadow_pipeline);
        pass.set_bind_group(0, &self.shadow_surface_bind_group, &[]);
        pass.set_vertex_buffer(0, self.unit_quad.slice(..));
        pass.set_vertex_buffer(1, self.shadow_instance_buffer.slice(..));
        pass.draw(0..6, 0..self.shadow_instance_count);
    }

    // The alpha lanes are patched only by the fixed modal-focus transition table.
    // This pass is isolated from static rounded surfaces so each ring receives its
    // own SDF outline metadata indexed from zero rather than UI instance offsets.
    fn draw_focus_rings<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>, tile_mask: Option<u64>) {
        if self.focus_ring_instance_count == 0 { return; }
        let Some(plan) = self.modal_focus_visual_plan.as_ref() else { return; };
        if let Some(mask) = tile_mask {
            if !plan.entries.iter().any(|entry| entry.tile_mask & mask != 0) { return; }
        }
        pass.set_pipeline(&self.focus_ring_pipeline);
        pass.set_bind_group(0, &self.focus_ring_bind_group, &[]);
        pass.set_vertex_buffer(0, self.unit_quad.slice(..));
        pass.set_vertex_buffer(1, self.focus_ring_instance_buffer.slice(..));
        pass.draw(0..6, 0..self.focus_ring_instance_count);
    }

    // Slot 0 is the compiler-reserved root canvas quad. It must establish the
    // opaque background before shadow layers, otherwise the root would erase the
    // entire shadow pass. Remaining slots preserve the compiler's frozen DFS order.
    fn draw_full_static_with_shadows<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>) {
        if self.instances.is_empty() { return; }
        pass.set_vertex_buffer(0, self.unit_quad.slice(..));
        pass.set_vertex_buffer(1, self.instance_buffer.slice(..));
        pass.set_pipeline(&self.static_pipeline);
        pass.set_bind_group(0, &self.rounded_surface_bind_group, &[]);
        pass.draw(0..6, 0..1);
        self.draw_shadow_surfaces(pass);
        if self.instances.len() > 1 {
            pass.set_vertex_buffer(0, self.unit_quad.slice(..));
            pass.set_vertex_buffer(1, self.instance_buffer.slice(..));
            pass.set_pipeline(&self.static_pipeline);
            pass.set_bind_group(0, &self.rounded_surface_bind_group, &[]);
            pass.draw(0..6, 1..self.instances.len() as u32);
        }
    }

    fn redraw_full_replay(&mut self, measure_gpu: bool, cpu_started: Instant) -> (SubmittedTileStats, Option<f64>, u128) {
        let mut encoder=self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor{label:Some("noir-full-replay-canvas")});
        self.encode_packet_activity(&mut encoder, 0);
        if measure_gpu { if let Some(timer)=self.gpu_timer.as_ref() { encoder.write_timestamp(&timer.query_set, 0); } }
        { let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor{label:Some("noir-full-replay-canvas-pass"),color_attachments:&[Some(wgpu::RenderPassColorAttachment{view:&self.canvas_view,resolve_target:None,depth_slice:None,ops:wgpu::Operations{load:wgpu::LoadOp::Clear(wgpu::Color{r:0.008,g:0.012,b:0.025,a:1.0}),store:wgpu::StoreOp::Store}})],depth_stencil_attachment:None,timestamp_writes:None,occlusion_query_set: None, multiview_mask: None});
            self.draw_full_static_with_shadows(&mut pass);
            self.draw_focus_rings(&mut pass, None);
            self.draw_all_glyph_packets(&mut pass);
        }
        if measure_gpu { if let Some(timer)=self.gpu_timer.as_ref() {
            encoder.write_timestamp(&timer.query_set, 1);
            encoder.resolve_query_set(&timer.query_set, 0..2, &timer.resolve_buffer, 0);
            encoder.copy_buffer_to_buffer(&timer.resolve_buffer, 0, &timer.readback_buffer, 0, 16);
        } }
        self.queue.submit(Some(encoder.finish()));
        let cpu_event_to_submit_ns = cpu_started.elapsed().as_nanos();
        let gpu_elapsed_ns = if measure_gpu { self.read_gpu_timestamp_ns() } else { None };
        (SubmittedTileStats { tile_count: 1, glyph_draw_count: self.scene.glyph_draw_packets.len(), glyph_instance_count: self.scene.glyph_placement_plan.len() as u32 }, gpu_elapsed_ns, cpu_event_to_submit_ns)
    }

    fn redraw_canvas_full(&mut self) {
        let mut encoder=self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor{label:Some("noir-full-canvas")});
        self.encode_packet_activity(&mut encoder, 0);
        { let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor{label:Some("noir-full-canvas-pass"),color_attachments:&[Some(wgpu::RenderPassColorAttachment{view:&self.canvas_view,resolve_target:None,depth_slice:None,ops:wgpu::Operations{load:wgpu::LoadOp::Clear(wgpu::Color{r:0.008,g:0.012,b:0.025,a:1.0}),store:wgpu::StoreOp::Store}})],depth_stencil_attachment:None,timestamp_writes:None,occlusion_query_set: None, multiview_mask: None});
          self.draw_full_static_with_shadows(&mut pass); self.draw_focus_rings(&mut pass, None); self.draw_all_glyph_packets(&mut pass); }
        self.queue.submit(Some(encoder.finish())); self.canvas_dirty=false;
    }
    fn redraw_selected_tiles(&mut self, request: RenderRequest, measure_gpu: bool, cpu_started: Option<Instant>) -> (SubmittedTileStats, Option<f64>, Option<u128>) {
        let selected_mask = request.tile_mask;
        if selected_mask == 0 { self.canvas_dirty = false; return (SubmittedTileStats::default(), None, cpu_started.map(|start| start.elapsed().as_nanos())); }
        let Some(schedule)=self.scene.render_schedules.first() else { self.redraw_canvas_full(); return (SubmittedTileStats::default(), None, cpu_started.map(|start| start.elapsed().as_nanos())); };
        println!("tile-redraw selected-mask=0x{selected_mask:016x}");
        let mut stats = SubmittedTileStats::default();
        let mut encoder=self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor{label:Some("noir-selected-tile-canvas")});
        self.encode_packet_activity(&mut encoder, request.packet_worklist_index);
        if measure_gpu { if let Some(timer)=self.gpu_timer.as_ref() { encoder.write_timestamp(&timer.query_set, 0); } }
        { let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor{label:Some("noir-selected-tile-canvas-pass"),color_attachments:&[Some(wgpu::RenderPassColorAttachment{view:&self.canvas_view,resolve_target:None,depth_slice:None,ops:wgpu::Operations{load:wgpu::LoadOp::Load,store:wgpu::StoreOp::Store}})],depth_stencil_attachment:None,timestamp_writes:None,occlusion_query_set: None, multiview_mask: None});
          for (tile_index, tile) in schedule.tiles.iter().enumerate() {
              if selected_mask & (1u64 << tile_index) == 0 { continue; }
              stats.tile_count += 1;
              stats.glyph_draw_count += tile.glyph_packet_ranges.len();
              stats.glyph_instance_count += tile.glyph_packet_ranges.iter().map(|range| range.placement_count).sum::<u32>();
              println!("tile-submit tile={tile_index}");
              let scissor_x = (tile.x.max(0.0) as u32).min(self.config.width.saturating_sub(1));
              let scissor_y = (tile.y.max(0.0) as u32).min(self.config.height.saturating_sub(1));
              let scissor_width = (tile.width.max(1.0) as u32).min(self.config.width.saturating_sub(scissor_x));
              let scissor_height = (tile.height.max(1.0) as u32).min(self.config.height.saturating_sub(scissor_y));
              pass.set_scissor_rect(scissor_x, scissor_y, scissor_width.max(1), scissor_height.max(1));
              pass.set_pipeline(&self.static_pipeline); pass.set_bind_group(0, &self.rounded_surface_bind_group, &[]); pass.set_vertex_buffer(0,self.unit_quad.slice(..)); pass.set_vertex_buffer(1,self.clear_buffer.slice(..)); pass.draw(0..6,0..1);
              self.draw_shadow_surfaces(&mut pass);
              self.draw_ranges(&mut pass,tile.draw_ranges.iter());
              self.draw_focus_rings(&mut pass, Some(1u64 << tile_index));
              self.draw_tile_glyph_packets(&mut pass, tile_index, &tile.glyph_packet_ranges,
                                           request.packet_worklist_index == RenderRequest::NO_PACKETS);
          } }
        if measure_gpu { if let Some(timer)=self.gpu_timer.as_ref() {
            encoder.write_timestamp(&timer.query_set, 1);
            encoder.resolve_query_set(&timer.query_set, 0..2, &timer.resolve_buffer, 0);
            encoder.copy_buffer_to_buffer(&timer.resolve_buffer, 0, &timer.readback_buffer, 0, 16);
        } }
        self.queue.submit(Some(encoder.finish()));
        let cpu_event_to_submit_ns = cpu_started.map(|start| start.elapsed().as_nanos());
        self.canvas_dirty=false;
        let gpu_elapsed_ns = if measure_gpu { self.read_gpu_timestamp_ns() } else { None };
        (stats, gpu_elapsed_ns, cpu_event_to_submit_ns)
    }

    fn patch_scroll_instance_y(&mut self, offset: usize, y: f32) {
        assert!(offset >= 4 && (offset - 4) % std::mem::size_of::<QuadInstance>() == 0,
                "compiler scroll instance patch has invalid ABI offset {}", offset);
        let slot = (offset - 4) / std::mem::size_of::<QuadInstance>();
        self.instances[slot].pos[1] = y;
        self.queue.write_buffer(&self.instance_buffer, offset as u64, bytemuck::bytes_of(&y));
    }

    fn patch_scroll_glyph_y(&mut self, offset: usize, y: f32) {
        assert!(offset >= 4 && (offset - 4) % GLYPH_PLACEMENT_BYTES == 0,
                "compiler scroll glyph patch has invalid ABI offset {}", offset);
        let slot = (offset - 4) / GLYPH_PLACEMENT_BYTES;
        self.placements[slot].pos[1] = y;
        self.queue.write_buffer(&self.placement_buffer, offset as u64, bytemuck::bytes_of(&y));
    }

    fn patch_scroll_glyph_id(&mut self, offset: usize, glyph_id: u32) {
        assert!(offset + 4 <= self.initial_glyph_bytes.len(),
                "compiler recycling glyph data patch has invalid ABI offset {}", offset);
        self.queue.write_buffer(&self.glyph_buffer, offset as u64, &glyph_id.to_le_bytes());
    }

    fn apply_compact_register_scroll(&mut self, list_index: usize, target: usize) {
        let (id, logical_capacity, physical_slots, visible_rows, instance_offsets, glyph_slots, instance_y, glyph_y, table) = {
            let plan = &self.virtual_lists[list_index];
            (plan.id.clone(), plan.logical_capacity, plan.physical_slots, plan.visible_rows, plan.row_instance_offsets.clone(), plan.row_glyph_slots.clone(), plan.row_base_instance_y.clone(), plan.row_base_glyph_y.clone(), plan.data_register_table.clone().expect("compact register table admitted at startup"))
        };
        let mut glyph_patch_count = 0usize;
        for physical in 0..physical_slots {
            let local = (physical + physical_slots - (target % physical_slots)) % physical_slots;
            let visible = local < visible_rows;
            let logical = target + local;
            for (index, offset) in instance_offsets[physical].iter().enumerate() {
                let y = if visible { instance_y[local][index] } else { -3.0 };
                self.patch_scroll_instance_y(offset + 4, y);
            }
            for (index, slot) in glyph_slots[physical].iter().enumerate() {
                let y = if visible { glyph_y[local][index] } else { -3.0 };
                self.patch_scroll_glyph_y(slot * GLYPH_PLACEMENT_BYTES + 4, y);
            }
            for (glyph_index, slot) in glyph_slots[physical].iter().enumerate() {
                let glyph_id = if logical < logical_capacity { table.glyph_ids[logical * table.register_width + glyph_index] } else { 1u32 << 16 };
                self.patch_scroll_glyph_id(slot * GLYPH_CELL_BYTES, glyph_id);
                glyph_patch_count += 1;
            }
            self.virtual_lists[list_index].ring_slots[physical] = if logical < logical_capacity { logical } else { logical_capacity };
        }
        self.virtual_lists[list_index].current_viewport_slot = target;
        let tiles = (target..target + visible_rows).map(|logical| logical % physical_slots).collect::<Vec<_>>();
        self.sync_log_browser_row_colors(list_index);
        println!("compact-register scroll: list={} table={} capacity={} target={} row-tiles={:?} physical-slots={} glyph-id-patches={} template=ring-v1", id, table.id, logical_capacity, target, tiles, physical_slots, glyph_patch_count);
    }

    fn patch_compact_data_register(&mut self, list_id: &str, logical_index: usize, value: &str) -> Result<()> {
        let list_index = self.virtual_lists.iter().position(|plan| plan.id == list_id)
            .with_context(|| format!("unknown compact virtual list {list_id}"))?;
        let (register_width, atlas_page, logical_capacity, glyph_slots, current, visible_rows, physical_slots) = {
            let plan = &self.virtual_lists[list_index];
            let table = plan.data_register_table.as_ref().context("data register patch requires compact data-register-table")?;
            (table.register_width, table.atlas_page, plan.logical_capacity, plan.row_glyph_slots.clone(), plan.current_viewport_slot, plan.visible_rows, plan.physical_slots)
        };
        anyhow::ensure!(logical_index < logical_capacity,
                        "data-register patch logical index exceeds fixed capacity");
        let glyphs = compact_register_glyphs(value, register_width, atlas_page)?;
        {
            let table = self.virtual_lists[list_index].data_register_table.as_mut().expect("admitted compact table");
            let start = logical_index * register_width;
            table.glyph_ids[start..start + register_width].copy_from_slice(&glyphs);
        }
        let visible = current <= logical_index && logical_index < current + visible_rows;
        if visible {
            let physical_slot = logical_index % physical_slots;
            for (glyph_index, slot) in glyph_slots[physical_slot].iter().enumerate() { self.patch_scroll_glyph_id(slot * GLYPH_CELL_BYTES, glyphs[glyph_index]); }
            self.enqueue_render(RenderRequest::scroll(list_index, current), "compact-register-data-patch");
        }
        println!("compact-register patch: list={} logical={} visible={} glyph-cells={} fixed-width={}", list_id, logical_index, visible, glyph_slots[logical_index % physical_slots].len(), register_width);
        Ok(())
    }

    fn apply_compact_data_update_batch(&mut self, list_id: &str, updates: &[(usize, String)]) -> Result<()> {
        let list_index = self.virtual_lists.iter().position(|plan| plan.id == list_id)
            .with_context(|| format!("unknown compact virtual list {list_id}"))?;
        let (register_width, atlas_page, logical_capacity, glyph_slots, current, visible_rows, physical_slots) = {
            let plan = &self.virtual_lists[list_index];
            let table = plan.data_register_table.as_ref().context("data-update-batch requires compact data-register-table")?;
            (table.register_width, table.atlas_page, plan.logical_capacity, plan.row_glyph_slots.clone(), plan.current_viewport_slot, plan.visible_rows, plan.physical_slots)
        };
        let mut seen = std::collections::HashSet::new();
        let mut visible_rows_to_patch = Vec::new();
        let mut arena_only = 0usize;
        for (logical_index, value) in updates {
            anyhow::ensure!(seen.insert(*logical_index) && *logical_index < logical_capacity,
                            "data-update-batch violates fixed logical index proof");
            let glyphs = compact_register_glyphs(value, register_width, atlas_page)?;
            let table = self.virtual_lists[list_index].data_register_table.as_mut().expect("admitted compact table");
            let start = logical_index * register_width;
            table.glyph_ids[start..start + register_width].copy_from_slice(&glyphs);
            if current <= *logical_index && *logical_index < current + visible_rows {
                let physical = *logical_index % physical_slots;
                for (glyph_index, slot) in glyph_slots[physical].iter().enumerate() { self.patch_scroll_glyph_id(slot * GLYPH_CELL_BYTES, glyphs[glyph_index]); }
                visible_rows_to_patch.push(*logical_index);
            } else { arena_only += 1; }
        }
        // Application-level status metadata remains outside the frozen list ABI. If this
        // list has a declared status dashboard, the same verified update batch refreshes
        // its color source before reusing the existing row-color patch addresses.
        if let Some(plan_index) = self.log_browser_plans.iter().position(|plan| plan.list_index == list_index) {
            for (logical_index, value) in updates {
                self.log_levels[plan_index][*logical_index] = Self::log_level_from_record(value);
            }
            self.sync_log_browser_row_colors(list_index);
        }
        if !visible_rows_to_patch.is_empty() { self.enqueue_render(RenderRequest::scroll(list_index, current), "data-update-batch-visible-fusion"); }
        println!("data-update-batch: list={} updates={} visible={} arena-only={} gpu-glyph-writes={} render-request={}", list_id, updates.len(), visible_rows_to_patch.len(), arena_only, visible_rows_to_patch.len() * glyph_slots[0].len(), !visible_rows_to_patch.is_empty());
        Ok(())
    }

    fn execute_scene_data_update_batches(&mut self) -> Result<()> {
        let plans = self.virtual_lists.iter().map(|plan| {
            (plan.id.clone(), plan.data_update_batches.clone())
        }).collect::<Vec<_>>();
        for (list_id, batches) in plans {
            for batch in batches {
                let updates = batch.updates.iter().map(|update| (update.index, update.value.clone())).collect::<Vec<_>>();
                println!("scene-data-update-batch: id={} list={} table={} updates={} source=compiler-artifact", batch.id, list_id, batch.table, updates.len());
                self.apply_compact_data_update_batch(&list_id, &updates)?;
            }
        }
        Ok(())
    }

    fn log_level_from_record(value: &str) -> LogLevel {
        if value.starts_with("WARN ") { LogLevel::Warn }
        else if value.starts_with("ERROR ") { LogLevel::Error }
        else if value.starts_with("DEBUG ") { LogLevel::Debug }
        else { LogLevel::Info }
    }

    fn log_level_name(level: LogLevel) -> &'static str {
        match level { LogLevel::Info => "INFO", LogLevel::Warn => "WARN", LogLevel::Error => "ERROR", LogLevel::Debug => "DEBUG" }
    }

    fn log_level_for(&self, list_index: usize, logical: usize) -> Option<LogLevel> {
        let plan_index = self.log_browser_plans.iter().position(|plan| plan.list_index == list_index)?;
        self.log_levels.get(plan_index)?.get(logical).copied()
    }

    fn log_row_color(&self, list_index: usize, logical: usize) -> Option<[f32; 4]> {
        let plan_index = self.log_browser_plans.iter().position(|plan| plan.list_index == list_index)?;
        let level = self.log_level_for(list_index, logical)?;
        let color_index = match level { LogLevel::Info => 0, LogLevel::Warn => 1, LogLevel::Error => 2, LogLevel::Debug => 3 };
        Some(self.log_browser_plans[plan_index].level_colors[color_index])
    }

    fn patch_log_browser_detail(&mut self, list_index: usize, logical: usize) -> bool {
        let Some(plan) = self.log_browser_plans.iter().find(|plan| plan.list_index == list_index).cloned() else { return false; };
        let plan_index = self.log_browser_plans.iter().position(|candidate| candidate.id == plan.id).expect("cloned log browser plan must remain indexed");
        let level = self.log_levels[plan_index][logical];
        let value = format!("DETAIL {} SELECTED", Self::log_level_name(level));
        for (offset, ch) in plan.detail_glyph_offsets.iter().zip(value.chars().chain(std::iter::repeat(' '))) {
            let glyph_id = if ch == ' ' { 1u32 << 16 } else { (1u32 << 16) | (1 + (ch as u32 - 'A' as u32)) };
            self.queue.write_buffer(&self.glyph_buffer, *offset as u64, &glyph_id.to_le_bytes());
        }
        self.enqueue_render(RenderRequest::with_worklist(plan.detail_tile_mask, plan.packet_worklist_index), "log-browser-detail");
        println!("log-browser detail: id={} logical={} level={} glyph-writes={} tile-mask=0x{:016x} worklist={}",
                 plan.id, logical, Self::log_level_name(level), plan.detail_glyph_offsets.len(), plan.detail_tile_mask, plan.packet_worklist_index);
        true
    }

    fn sync_log_browser_row_colors(&mut self, list_index: usize) {
        if !self.log_browser_plans.iter().any(|plan| plan.list_index == list_index) { return; }
        let (viewport, visible_rows) = {
            let list = &self.virtual_lists[list_index];
            (list.current_viewport_slot, list.visible_rows)
        };
        for logical in viewport..viewport + visible_rows { self.patch_list_row_color(list_index, logical); }
    }

    fn execute_log_browser_append(&mut self, requested_id: &str) -> Result<()> {
        let plan = self.log_browser_plans.iter().find(|plan| plan.id == requested_id)
            .with_context(|| format!("unknown log browser {requested_id}"))?.clone();
        let updates = plan.append_updates.iter().map(|update| (update.index, update.value.clone())).collect::<Vec<_>>();
        self.apply_compact_data_update_batch(&self.virtual_lists[plan.list_index].id.clone(), &updates)?;
        let plan_index = self.log_browser_plans.iter().position(|candidate| candidate.id == plan.id).expect("log browser plan must remain indexed");
        for update in &plan.append_updates { self.log_levels[plan_index][update.index] = Self::log_level_from_record(&update.value); }
        self.sync_log_browser_row_colors(plan.list_index);
        println!("log-browser append: id={} batch={} records={} tail={}..{} source=compiler-artifact",
                 plan.id, plan.append_batch_id, plan.append_updates.len(), plan.append_updates.first().unwrap().index, plan.append_updates.last().unwrap().index);
        Ok(())
    }

    fn list_row_at_cursor(&self) -> Option<(usize, usize)> {
        for interaction in &self.list_interactions {
            let plan = &self.virtual_lists[interaction.list_index];
            let scissor = &plan.scroll_scissor;
            if self.cursor[0] >= scissor.x && self.cursor[0] < scissor.x + scissor.width
                && self.cursor[1] >= scissor.y && self.cursor[1] < scissor.y + scissor.height {
                let local = ((self.cursor[1] - scissor.y) / plan.row_height as f32).floor() as usize;
                if local < plan.visible_rows {
                    let logical = plan.current_viewport_slot + local;
                    if logical <= interaction.maximum_logical_row { return Some((interaction.list_index, logical)); }
                }
            }
        }
        None
    }

    fn material_observability_workbench_list_input_admitted(&self, list_index: usize) -> bool {
        let Some(plan) = &self.material_observability_workbench_plan else { return true; };
        let admitted = plan.selected_index == plan.systems_view_index && list_index == plan.systems_list_index;
        if !admitted {
            println!("material-workbench list-input-gated: active-view={} systems-view={} requested-list={} systems-list={}",
                     plan.views[plan.selected_index].destination_id, plan.views[plan.systems_view_index].destination_id,
                     list_index, plan.systems_list_index);
        }
        admitted
    }

    fn patch_list_row_color(&mut self, list_index: usize, logical: usize) {
        let interaction = self.list_interactions[list_index].clone();
        let (list_id, viewport, visible_rows, physical_slots) = {
            let plan = &self.virtual_lists[list_index];
            (plan.id.clone(), plan.current_viewport_slot, plan.visible_rows, plan.physical_slots)
        };
        if logical < viewport || logical >= viewport + visible_rows { return; }
        let physical = logical % physical_slots;
        let offset = interaction.row_color_offsets[physical];
        let instance = offset / std::mem::size_of::<QuadInstance>();
        let color = if self.list_selected_rows[list_index] == Some(logical) { interaction.selected_color }
            else if self.list_hovered_rows[list_index] == Some(logical) { interaction.hover_color }
            else { self.log_row_color(list_index, logical).unwrap_or(self.initial_instances[instance].color) };
        self.instances[instance].color = color;
        self.queue.write_buffer(&self.instance_buffer, offset as u64, bytemuck::cast_slice(&color));
        let level = self.log_level_for(list_index, logical).map(Self::log_level_name).unwrap_or("BASE");
        println!("list-interaction-patch: list={} logical={} physical={} color_offset={} level={} selected={} hovered={}", list_id, logical, physical, offset, level, self.list_selected_rows[list_index] == Some(logical), self.list_hovered_rows[list_index] == Some(logical));
    }

    fn set_list_hover_from_cursor(&mut self) -> bool {
        if !self.material_observability_workbench_list_input_admitted(0) { return false; }
        let next = self.list_row_at_cursor();
        let mut consumed = false;
        for index in 0..self.list_interactions.len() {
            let candidate = next.and_then(|(list, row)| if list == index { Some(row) } else { None });
            if self.list_hovered_rows[index] == candidate { consumed |= candidate.is_some(); continue; }
            let old = self.list_hovered_rows[index];
            self.list_hovered_rows[index] = candidate;
            if let Some(row) = old { self.patch_list_row_color(index, row); }
            if let Some(row) = candidate { self.patch_list_row_color(index, row); self.enqueue_render(RenderRequest::scroll(index, self.virtual_lists[index].current_viewport_slot), "list-hover"); consumed = true; }
        }
        consumed
    }

    fn select_list_logical(&mut self, index: usize, logical: usize) -> bool {
        if !self.material_observability_workbench_list_input_admitted(index) { return false; }
        let interaction = &self.list_interactions[index];
        if logical < interaction.minimum_logical_row || logical > interaction.maximum_logical_row { return false; }
        let old = self.list_selected_rows[index];
        self.list_selected_rows[index] = Some(logical);
        if let Some(row) = old { self.patch_list_row_color(index, row); }
        self.patch_list_row_color(index, logical);
        self.patch_log_browser_detail(index, logical);
        self.enqueue_render(RenderRequest::scroll(index, self.virtual_lists[index].current_viewport_slot), "list-selection");
        println!("list-selection: list={} logical={} physical={}", self.virtual_lists[index].id, logical, logical % self.virtual_lists[index].physical_slots);
        true
    }

    fn select_list_from_cursor(&mut self) -> bool {
        let Some((index, logical)) = self.list_row_at_cursor() else { return false; };
        self.select_list_logical(index, logical)
    }

    fn inject_list_release(&mut self, list_id: &str, logical: usize) -> Result<()> {
        let index = self.virtual_lists.iter().position(|plan| plan.id == list_id)
            .with_context(|| format!("unknown list interaction id {list_id}"))?;
        anyhow::ensure!(logical >= self.virtual_lists[index].current_viewport_slot && logical < self.virtual_lists[index].current_viewport_slot + self.virtual_lists[index].visible_rows,
                        "injected release must target current compiler viewport");
        anyhow::ensure!(self.select_list_logical(index, logical), "injected release rejected by interaction proof");
        println!("list-interaction-inject-release: list={} logical={} source=integration-test", list_id, logical);
        Ok(())
    }

    // `row_activation_plans` has already proven that this list, Action Slot, coalesced batch,
    // action-local tile mask, physical-slot rule and no-packets worklist form one closed ABI.
    // At input time we only read the selected logical row and dispatch the precomputed batch.
    fn activate_selected_list_row_for(&mut self, requested_list_id: Option<&str>) -> bool {
        for plan in self.row_activation_plans.clone() {
            let list_id = self.virtual_lists[plan.list_index].id.clone();
            if requested_list_id.is_some_and(|requested| requested != list_id) { continue; }
            if !self.material_observability_workbench_list_input_admitted(plan.list_index) { continue; }
            let Some(logical) = self.list_selected_rows[plan.list_index] else { continue; };
            let physical = logical % self.virtual_lists[plan.list_index].physical_slots;
            println!("row-activation: list={} logical={} physical={} action-slot={} batch={} action-tile-mask=0x{:016x} worklist={}",
                     list_id, logical, physical, plan.action_slot_index, plan.activate_batch_id,
                     plan.tile_mask, plan.packet_worklist_index);
            // Reuse the sole coalesced executor: winner-write ordering, batch-local composite
            // worklist selection, and RenderRequest enqueue remain exactly the verified path.
            self.execute_coalesced_batch(&plan.activate_batch_id);
            // A log detail panel shares the action-local tile but owns a disjoint fixed glyph range.
            // Reapply it after the generic dynamic action glyph patch so selected content remains visible.
            self.patch_log_browser_detail(plan.list_index, logical);
            return true;
        }
        false
    }

    fn activate_selected_list_row(&mut self) -> bool {
        self.activate_selected_list_row_for(None)
    }

    fn inject_row_activate(&mut self, list_id: &str) -> Result<()> {
        let plan = self.row_activation_plans.iter()
            .find(|plan| self.virtual_lists[plan.list_index].id == list_id)
            .with_context(|| format!("unknown row activation list {list_id}"))?;
        anyhow::ensure!(self.list_selected_rows[plan.list_index].is_some(),
                        "--inject-row-activate requires a selected logical row; precede it with --inject-list-release");
        anyhow::ensure!(self.activate_selected_list_row_for(Some(list_id)),
                        "injected row activation rejected by compiler proof");
        println!("row-activation-inject: list={} source=integration-test", list_id);
        Ok(())
    }

    fn navigate_list_selection(&mut self, direction: i32) -> bool {
        if self.list_interactions.is_empty() { return false; }
        let index = 0usize;
        if !self.material_observability_workbench_list_input_admitted(index) { return false; }
        let interaction = &self.list_interactions[index];
        let current = self.list_selected_rows[index].unwrap_or(interaction.minimum_logical_row);
        let target = if direction < 0 { current.saturating_sub(1).max(interaction.minimum_logical_row) } else { (current + 1).min(interaction.maximum_logical_row) };
        if target == current && self.list_selected_rows[index].is_some() { println!("list-navigation boundary: logical={}", current); return true; }
        let viewport = self.virtual_lists[index].current_viewport_slot;
        if target < viewport || target >= viewport + self.virtual_lists[index].visible_rows {
            let next_viewport = if target < viewport { target } else { target + 1 - self.virtual_lists[index].visible_rows };
            self.apply_compact_register_scroll(index, next_viewport);
            self.sync_scrollbar_thumb_for_list(index, "scrollbar-thumb-keyboard-sync");
        }
        let old = self.list_selected_rows[index];
        self.list_selected_rows[index] = Some(target);
        if let Some(row) = old { self.patch_list_row_color(index, row); }
        self.patch_list_row_color(index, target);
        self.enqueue_render(RenderRequest::scroll(index, self.virtual_lists[index].current_viewport_slot), "list-keyboard-navigation");
        println!("list-navigation: logical={} -> {} viewport={}", current, target, self.virtual_lists[index].current_viewport_slot);
        true
    }

    fn execute_list_navigation(&mut self, key: ListNavigationKey) -> bool {
        let Some(plan) = self.list_navigation_plans.first().cloned() else { return false; };
        if !self.material_observability_workbench_list_input_admitted(plan.list_index) { return false; }
        let current = self.virtual_lists[plan.list_index].current_viewport_slot;
        let target = match key {
            ListNavigationKey::PageUp => current.saturating_sub(plan.page_step),
            ListNavigationKey::PageDown => (current + plan.page_step).min(plan.max_viewport),
            ListNavigationKey::Home => 0,
            ListNavigationKey::End => plan.max_viewport,
        };
        if target == current {
            println!("list-navigation-plan boundary: id={} key={:?} viewport={} tile-mask=0x{:016x} worklist=no-packets",
                     plan.id, key, current, plan.tile_mask);
            return true;
        }
        let changed = self.scroll_compact_list_to(plan.list_index, target, "list-navigation-plan");
        debug_assert!(changed, "non-boundary compiler navigation transition must change viewport");
        println!("list-navigation-plan: id={} key={:?} list={} from={} to={} page-step={} tile-mask=0x{:016x} worklist=no-packets",
                 plan.id, key, self.virtual_lists[plan.list_index].id, current, target,
                 plan.page_step, plan.tile_mask);
        true
    }

    fn scroll_virtual_list(&mut self, direction: i32) {
        if direction == 0 { return; }
        for list_index in 0..self.virtual_lists.len() {
            if !self.material_observability_workbench_list_input_admitted(list_index) { continue; }
            let current = self.virtual_lists[list_index].current_viewport_slot;
            let max_scroll = self.virtual_lists[list_index].logical_capacity - self.virtual_lists[list_index].visible_rows;
            let target = if direction > 0 { (current + 1).min(max_scroll) } else { current.saturating_sub(1) };
            if self.virtual_lists[list_index].data_register_table.is_some() {
                if target == current { println!("compact-register scroll boundary: list={} viewport={}", self.virtual_lists[list_index].id, current); continue; }
                self.apply_compact_register_scroll(list_index, target);
                self.enqueue_render(RenderRequest::scroll(list_index, target), "compact-register-scroll");
                self.sync_scrollbar_thumb_for_list(list_index, "scrollbar-thumb-wheel-sync");
                continue;
            }
            let transition = self.virtual_lists[list_index].scroll_transitions.iter()
                .find(|transition| transition.from_slot == current && transition.to_slot == target).cloned();
            let Some(transition) = transition else {
                println!("virtual-list scroll boundary: list={} viewport={} direction={}", self.virtual_lists[list_index].id, current, direction);
                continue;
            };
            for patch in &transition.instance_y_patches { self.patch_scroll_instance_y(patch.offset, patch.y); }
            for patch in &transition.glyph_y_patches { self.patch_scroll_glyph_y(patch.offset, patch.y); }
            for patch in &transition.glyph_id_patches { self.patch_scroll_glyph_id(patch.offset, patch.glyph_id); }
            self.virtual_lists[list_index].current_viewport_slot = target;
            println!("virtual-list scroll: list={} from={} to={} row-tiles={:?} instance-patches={} glyph-patches={} glyph-id-patches={} recycling={} scissor=({}, {}, {}, {})",
                     self.virtual_lists[list_index].id, current, target, transition.visible_row_tile_ids,
                     transition.instance_y_patches.len(), transition.glyph_y_patches.len(), transition.glyph_id_patches.len(), self.virtual_lists[list_index].recycling,
                     transition.scissor.x, transition.scissor.y, transition.scissor.width, transition.scissor.height);
            self.enqueue_render(RenderRequest::scroll(list_index, target), "virtual-list-scroll");
        }
    }

    fn sync_scrollbar_thumb_for_list(&mut self, list_index: usize, source: &str) {
        let viewport = self.virtual_lists[list_index].current_viewport_slot;
        let plans = self.scrollbar_plans.iter().filter(|plan| plan.list_index == list_index).cloned().collect::<Vec<_>>();
        for plan in plans {
            self.patch_scrollbar_thumb(&plan, viewport);
            self.enqueue_render(RenderRequest::no_packets(plan.tile_mask), source);
            println!("scrollbar-thumb-sync: id={} list={} viewport={} thumb-offset={} tile-mask=0x{:016x} worklist=no-packets",
                     plan.id, self.virtual_lists[list_index].id, viewport, plan.thumb_instance_offset, plan.tile_mask);
        }
    }

    fn scroll_compact_list_to(&mut self, list_index: usize, target: usize, source: &str) -> bool {
        let current = self.virtual_lists[list_index].current_viewport_slot;
        let max_viewport = self.virtual_lists[list_index].logical_capacity - self.virtual_lists[list_index].visible_rows;
        let target = target.min(max_viewport);
        if target == current { return false; }
        debug_assert!(self.virtual_lists[list_index].data_register_table.is_some(),
                      "scrollbar v1 admission requires compact direct-scroll list");
        self.apply_compact_register_scroll(list_index, target);
        self.enqueue_render(RenderRequest::scroll(list_index, target), source);
        self.sync_scrollbar_thumb_for_list(list_index, "scrollbar-thumb-scroll-sync");
        true
    }

    fn scrollbar_at_cursor(&self) -> Option<usize> {
        self.scrollbar_plans.iter().position(|plan|
            self.cursor[0] >= plan.track_x && self.cursor[0] < plan.track_x + plan.track_width
                && self.cursor[1] >= plan.track_y && self.cursor[1] < plan.track_y + plan.track_height)
    }

    fn scrollbar_target_viewport(&self, plan: &CompiledScrollbarPlan) -> usize {
        let travel = plan.track_height - plan.thumb_height;
        debug_assert!(travel > 0.0 && plan.max_viewport > 0, "compiler admitted a zero scrollbar travel/domain");
        let thumb_top = (self.cursor[1] - plan.track_y - plan.thumb_height * 0.5).clamp(0.0, travel);
        ((thumb_top / travel) * plan.max_viewport as f32).round() as usize
    }

    fn patch_scrollbar_thumb(&mut self, plan: &CompiledScrollbarPlan, viewport: usize) {
        let travel = plan.track_height - plan.thumb_height;
        let thumb_top = travel * viewport as f32 / plan.max_viewport as f32;
        let screen_top = plan.track_y + thumb_top;
        let ndc_y = 1.0 - 2.0 * (screen_top + plan.thumb_height) / self.canvas_height as f32;
        self.patch_instance_f32((plan.thumb_instance_offset + 4) as u64, ndc_y);
    }

    fn drag_scrollbar(&mut self, index: usize, source: &str) -> bool {
        let plan = self.scrollbar_plans[index].clone();
        let target = self.scrollbar_target_viewport(&plan);
        let changed = self.scroll_compact_list_to(plan.list_index, target, source);
        let admitted_viewport = self.virtual_lists[plan.list_index].current_viewport_slot;
        // A changed viewport already receives exactly one patch/request via the common
        // scroll synchronizer. Boundary drags still refresh their fixed thumb locally.
        if !changed {
            self.patch_scrollbar_thumb(&plan, admitted_viewport);
            self.enqueue_render(RenderRequest::no_packets(plan.tile_mask), "scrollbar-thumb-local");
        }
        println!("scrollbar-drag: id={} list={} pointer-y={:.3} viewport={} thumb-offset={} tile-mask=0x{:016x} worklist=no-packets changed={}",
                 plan.id, self.virtual_lists[plan.list_index].id, self.cursor[1], admitted_viewport,
                 plan.thumb_instance_offset, plan.tile_mask, changed);
        true
    }

    fn begin_scrollbar_drag(&mut self) -> bool {
        let Some(index) = self.scrollbar_at_cursor() else { return false; };
        self.active_scrollbar = Some(index);
        self.drag_scrollbar(index, "scrollbar-press")
    }

    fn update_scrollbar_drag(&mut self) -> bool {
        let Some(index) = self.active_scrollbar else { return false; };
        self.drag_scrollbar(index, "scrollbar-drag")
    }

    fn end_scrollbar_drag(&mut self) -> bool {
        let Some(index) = self.active_scrollbar.take() else { return false; };
        self.drag_scrollbar(index, "scrollbar-release")
    }

    fn redraw_virtual_scroll(&mut self, list_index: usize, viewport_slot: usize) {
        let (plan_id, scissor, row_draw_ranges, row_glyph_subranges) = {
            let plan = self.virtual_lists.get(list_index).expect("compiler virtual list index admitted at startup");
            let visible_tiles = if plan.data_register_table.is_some() {
                (viewport_slot..viewport_slot + plan.visible_rows).map(|logical| logical % plan.physical_slots).collect::<Vec<_>>()
            } else {
                plan.scroll_transitions.iter().find(|transition| transition.to_slot == viewport_slot)
                    .expect("compiler viewport slot has an admitted transition").visible_row_tile_ids.clone()
            };
            let row_draw_ranges = visible_tiles.iter().map(|tile| {
                let range = plan.row_draw_ranges[*tile].clone();
                DrawRange { first_instance: range.first, instance_count: range.count }
            }).collect::<Vec<_>>();
            let row_glyph_subranges = visible_tiles.iter().map(|tile| plan.row_glyph_subranges[*tile].clone()).collect::<Vec<_>>();
            (plan.id.clone(), plan.scroll_scissor.clone(), row_draw_ranges, row_glyph_subranges)
        };
        let transition = VirtualScrollTransition { from_slot: viewport_slot, to_slot: viewport_slot, visible_row_tile_ids: Vec::new(), instance_y_patches: Vec::new(), glyph_y_patches: Vec::new(), glyph_id_patches: Vec::new(), scissor };
        let scissor_x = (transition.scissor.x.max(0.0).round() as u32).min(self.config.width.saturating_sub(1));
        let scissor_y = (transition.scissor.y.max(0.0).round() as u32).min(self.config.height.saturating_sub(1));
        let scissor_width = (transition.scissor.width.max(1.0).round() as u32).min(self.config.width.saturating_sub(scissor_x)).max(1);
        let scissor_height = (transition.scissor.height.max(1.0).round() as u32).min(self.config.height.saturating_sub(scissor_y)).max(1);
        let submitted_quad_instances = row_draw_ranges.iter().map(|range| range.instance_count).sum::<u32>();
        let submitted_glyph_placements = row_glyph_subranges.iter().map(|range| range.count).sum::<u32>();
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("noir-virtual-list-scroll") });
        self.encode_packet_activity(&mut encoder, RenderRequest::NO_PACKETS);
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor { label: Some("noir-virtual-list-scroll-pass"), color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: &self.canvas_view, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store } })], depth_stencil_attachment: None, timestamp_writes: None, occlusion_query_set: None, multiview_mask: None});
            pass.set_scissor_rect(scissor_x, scissor_y, scissor_width, scissor_height);
            pass.set_pipeline(&self.static_pipeline); pass.set_bind_group(0, &self.rounded_surface_bind_group, &[]); pass.set_vertex_buffer(0, self.unit_quad.slice(..)); pass.set_vertex_buffer(1, self.clear_buffer.slice(..)); pass.draw(0..6, 0..1);
            self.draw_ranges(&mut pass, row_draw_ranges.iter());
            self.draw_virtual_row_glyph_subranges(&mut pass, &row_glyph_subranges);
        }
        self.queue.submit(Some(encoder.finish()));
        self.canvas_dirty = false;
        println!("virtual-list scroll-submit: list={} viewport={} scissor={}x{}+{},{} quad-ranges={} quad-instances={} glyph-subranges={} glyph-placements={} worklist=no-packets", plan_id, viewport_slot, scissor_width, scissor_height, scissor_x, scissor_y, row_draw_ranges.len(), submitted_quad_instances, row_glyph_subranges.len(), submitted_glyph_placements);
    }

    fn redraw_canvas_requests(&mut self) {
        let requests = std::mem::take(&mut self.pending_render);
        for request in requests {
            if let (Some(list_index), Some(viewport_slot)) = (request.scroll_list_index, request.scroll_viewport_slot) {
                self.redraw_virtual_scroll(list_index, viewport_slot);
                continue;
            }
            match request.strategy {
                Some(CompilerStrategy::FullRedraw) => {
                    debug_assert_eq!(request.packet_worklist_index, RenderRequest::ALL_PACKETS,
                                     "full replay must use the compiler all-packets slot");
                    println!("strategy-executor full-redraw worklist={}", request.packet_worklist_index);
                    self.redraw_canvas_full();
                }
                Some(CompilerStrategy::PacketAware) => {
                    println!("strategy-executor packet-aware worklist={}", request.packet_worklist_index);
                    let packet_request = RenderRequest::with_worklist(self.all_schedule_tile_mask(), request.packet_worklist_index);
                    let _ = self.redraw_selected_tiles(packet_request, false, None);
                }
                Some(CompilerStrategy::Coalesced) | None => {
                    let _ = self.redraw_selected_tiles(request, false, None);
                }
            }
        }
        self.canvas_dirty = false;
    }

    fn expected_selected_tile_stats(&self, tile_mask: u64) -> SubmittedTileStats {
        let mut stats = SubmittedTileStats::default();
        if let Some(schedule) = self.scene.render_schedules.first() {
            for (tile_index, tile) in schedule.tiles.iter().enumerate() {
                if tile_mask & (1u64 << tile_index) == 0 { continue; }
                stats.tile_count += 1;
                stats.glyph_draw_count += tile.glyph_packet_ranges.len();
                stats.glyph_instance_count += tile.glyph_packet_ranges.iter().map(|range| range.placement_count).sum::<u32>();
            }
        }
        stats
    }

    fn action_write_plan_index(&self, action_index: usize) -> Result<Vec<FrameCoalescedWrite>> {
        let action_id = self.action_slot_ids.get(action_index)
            .with_context(|| format!("compiler action_index {action_index} outside Action Slot table"))?;
        let action = self.compiled_actions.get(action_index)
            .with_context(|| format!("compiler action_index {action_index} has no compiled plan"))?;
        let mut writes = Vec::new();
        for update in &action.gpu_updates {
            let offsets: Vec<usize> = if update.glyph_id_offsets.is_empty() {
                (0..update.glyph_count).map(|index| update.offset + index * GLYPH_CELL_BYTES).collect()
            } else { update.glyph_id_offsets.clone() };
            for offset in offsets { writes.push(FrameCoalescedWrite { task_id: action_id.clone(), offset, byte_length: 4 }); }
        }
        for update in &action.instance_updates {
            writes.push(FrameCoalescedWrite { task_id: action_id.clone(), offset: update.offset, byte_length: update.byte_length });
        }
        Ok(writes)
    }

    fn action_write_plan(&self, action_id: &str) -> Result<Vec<FrameCoalescedWrite>> {
        let action = self.scene.actions.get(action_id).with_context(|| format!("unknown compiler action {action_id}"))?;
        let mut writes = Vec::new();
        for update in &action.gpu_updates {
            let offsets: Vec<usize> = if update.glyph_id_offsets.is_empty() {
                (0..update.glyph_count).map(|index| update.offset + index * GLYPH_CELL_BYTES).collect()
            } else { update.glyph_id_offsets.clone() };
            for offset in offsets { writes.push(FrameCoalescedWrite { task_id: action_id.to_string(), offset, byte_length: 4 }); }
        }
        for update in &action.instance_updates {
            writes.push(FrameCoalescedWrite { task_id: action_id.to_string(), offset: update.offset, byte_length: 4 });
        }
        Ok(writes)
    }

    fn all_schedule_tile_mask(&self) -> u64 {
        self.scene.render_schedules.first().map(|schedule| {
            if schedule.tiles.len() == 64 { u64::MAX } else { (1u64 << schedule.tiles.len()) - 1 }
        }).unwrap_or(0)
    }

    fn compiler_selected_once(&mut self, batch_id: &str, measure_gpu: bool) -> Result<(SubmittedTileStats, Option<f64>, u128, usize, CompilerSelectedConsistency)> {
        self.reset_replay_state();
        let batch = self.coalesced_batches.get(batch_id).cloned().context("compiler-selected batch disappeared")?;
        let proof = self.scene.frame_coalesced_batches.iter().find(|candidate| candidate.id == batch_id)
            .and_then(|candidate| candidate.selection_proof.as_ref())
            .cloned()
            .context("compiler-selected activate batch has no startup-validated proof")?;
        let expected_write_bytes: usize = batch.winner_writes.iter().map(|write| write.byte_length).sum();
        let expected_mask = match batch.strategy {
            CompilerStrategy::FullRedraw | CompilerStrategy::PacketAware => self.all_schedule_tile_mask(),
            CompilerStrategy::Coalesced => batch.tile_mask,
        };
        let expected_stats = match batch.strategy {
            CompilerStrategy::FullRedraw => SubmittedTileStats {
                tile_count: 1,
                glyph_draw_count: self.scene.glyph_draw_packets.len(),
                glyph_instance_count: self.scene.glyph_placement_plan.len() as u32,
            },
            CompilerStrategy::PacketAware | CompilerStrategy::Coalesced => self.expected_selected_tile_stats(expected_mask),
        };
        let started = Instant::now();
        let (applied, applied_worklist) = self.apply_compiler_batch_writes(batch_id)
            .context("compiler-selected batch write application failed")?;
        anyhow::ensure!(applied.strategy == batch.strategy, "compiler-selected dispatcher strategy mutated after startup validation");
        let (observed_stats, gpu_elapsed_ns, cpu_event_to_submit_ns, observed_mask) = match batch.strategy {
            CompilerStrategy::FullRedraw => {
                let (stats, gpu, cpu) = self.redraw_full_replay(measure_gpu, started);
                (stats, gpu, cpu, expected_mask)
            }
            CompilerStrategy::PacketAware => {
                let (stats, gpu, cpu) = self.redraw_selected_tiles(RenderRequest::with_worklist(expected_mask, applied_worklist), measure_gpu, Some(started));
                (stats, gpu, cpu.unwrap_or(0), expected_mask)
            }
            CompilerStrategy::Coalesced => {
                let (stats, gpu, cpu) = self.redraw_selected_tiles(RenderRequest::with_worklist(batch.tile_mask, applied_worklist), measure_gpu, Some(started));
                (stats, gpu, cpu.unwrap_or(0), batch.tile_mask)
            }
        };
        let self_consistent = observed_mask == expected_mask
            && observed_stats.tile_count == expected_stats.tile_count
            && observed_stats.glyph_draw_count == expected_stats.glyph_draw_count
            && observed_stats.glyph_instance_count == expected_stats.glyph_instance_count
            && expected_write_bytes == applied.winner_writes.iter().map(|write| write.byte_length).sum::<usize>()
            && proof.winner.as_deref() == Some(batch.strategy.id());
        let consistency = CompilerSelectedConsistency {
            compiler_strategy_id: batch.strategy.id().to_string(),
            proof_profile_id: proof.profile_id.clone().unwrap_or_else(|| "none".to_string()),
            proof_winner: proof.winner.clone().unwrap_or_else(|| "missing".to_string()),
            actual_executor: batch.strategy.id().to_string(),
            expected_tile_mask_hex: format!("0x{expected_mask:016x}"),
            observed_tile_mask_hex: format!("0x{observed_mask:016x}"),
            expected_tile_count: expected_stats.tile_count,
            observed_tile_count: observed_stats.tile_count,
            expected_glyph_draw_count: expected_stats.glyph_draw_count,
            observed_glyph_draw_count: observed_stats.glyph_draw_count,
            expected_glyph_instance_count: expected_stats.glyph_instance_count,
            observed_glyph_instance_count: observed_stats.glyph_instance_count,
            expected_winner_write_bytes: expected_write_bytes,
            observed_winner_write_bytes: applied.winner_writes.iter().map(|write| write.byte_length).sum(),
            self_consistent,
        };
        anyhow::ensure!(consistency.self_consistent,
                        "compiler-selected replay {batch_id} diverged: mask {} != {}; tiles {} != {}; draws {} != {}; instances {} != {}; winner-bytes {} != {}; proof={:?} executor={}",
                        consistency.expected_tile_mask_hex, consistency.observed_tile_mask_hex,
                        consistency.expected_tile_count, consistency.observed_tile_count,
                        consistency.expected_glyph_draw_count, consistency.observed_glyph_draw_count,
                        consistency.expected_glyph_instance_count, consistency.observed_glyph_instance_count,
                        consistency.expected_winner_write_bytes, consistency.observed_winner_write_bytes,
                        consistency.proof_winner, consistency.actual_executor);
        Ok((observed_stats, gpu_elapsed_ns, cpu_event_to_submit_ns, expected_write_bytes, consistency))
    }

    fn replay_once(&mut self, mode: ReplayMode, batch_id: &str, measure_gpu: bool) -> Result<(SubmittedTileStats, Option<f64>, u128, usize)> {
        self.reset_replay_state();
        let batch = self.coalesced_batches.get(batch_id).cloned().context("replay batch disappeared")?;
        let action_index = batch.execution_refs.iter().find_map(|task_ref| match task_ref {
                    CompiledTaskRef::Action(index) => Some(*index),
            CompiledTaskRef::Transaction(_) | CompiledTaskRef::Transient(_) => None,
        }).context("replay batch has no compiler action task-ref")?;
        let action_id = self.action_slot_ids.get(action_index).cloned()
            .context("replay action_index outside Action Slot table")?;
        let started = Instant::now();
        match mode {
            ReplayMode::FullRedraw => {
                self.execute_coalesced_batch(batch_id);
                let (stats, gpu, cpu) = self.redraw_full_replay(measure_gpu, started);
                Ok((stats, gpu, cpu, batch.winner_writes.iter().map(|write| write.byte_length).sum()))
            }
            ReplayMode::PacketAware => {
                self.execute_coalesced_batch(batch_id);
                self.pending_render.clear();
                let selected = self.all_schedule_tile_mask();
                let (stats, gpu, cpu) = self.redraw_selected_tiles(RenderRequest::with_worklist(selected, RenderRequest::ALL_PACKETS), measure_gpu, Some(started));
                Ok((stats, gpu, cpu.unwrap_or(0), batch.winner_writes.iter().map(|write| write.byte_length).sum()))
            }
            ReplayMode::ActionAware => {
                let writes = self.action_write_plan(&action_id)?;
                self.apply_action_winner_writes(&action_id, &writes)?;
                let selected = *self.action_tile_masks.get(&action_id).context("action has no compiler tile mask")?;
                let (stats, gpu, cpu) = self.redraw_selected_tiles(RenderRequest::no_packets(selected), measure_gpu, Some(started));
                Ok((stats, gpu, cpu.unwrap_or(0), writes.iter().map(|write| write.byte_length).sum()))
            }
            ReplayMode::Coalesced => {
                self.execute_coalesced_batch(batch_id);
                let request = self.pending_render.pop().context("coalesced replay produced no RenderRequest")?;
                let (stats, gpu, cpu) = self.redraw_selected_tiles(request, measure_gpu, Some(started));
                Ok((stats, gpu, cpu.unwrap_or(0), batch.winner_writes.iter().map(|write| write.byte_length).sum()))
            }
            ReplayMode::CompilerSelected => {
                let (stats, gpu, cpu, bytes, _) = self.compiler_selected_once(batch_id, measure_gpu)?;
                Ok((stats, gpu, cpu, bytes))
            }
        }
    }

    fn run_replay_matrix(&mut self, report_path: &str, warmup_iterations: usize, sample_iterations: usize) -> Result<()> {
        anyhow::ensure!(sample_iterations > 0, "replay matrix sample_iterations must be positive");
        let mut workloads: Vec<String> = self.coalesced_batches.keys()
            .filter(|id| id.starts_with("coalesced-activate-"))
            .cloned().collect();
        workloads.sort();
        let modes = [ReplayMode::FullRedraw, ReplayMode::PacketAware, ReplayMode::ActionAware, ReplayMode::Coalesced, ReplayMode::CompilerSelected];
        let mut rows = Vec::new();
        for workload_id in workloads {
            for mode in modes {
                if matches!(mode, ReplayMode::CompilerSelected) {
                    for _ in 0..warmup_iterations { let _ = self.compiler_selected_once(&workload_id, false)?; }
                    let mut gpu_samples = Vec::new();
                    let mut cpu_samples = Vec::with_capacity(sample_iterations);
                    let mut final_stats = SubmittedTileStats::default();
                    let mut write_bytes = 0usize;
                    let mut final_consistency = None;
                    for _ in 0..sample_iterations {
                        let (stats, gpu_ns, cpu_ns, bytes, consistency) = self.compiler_selected_once(&workload_id, true)?;
                        final_stats = stats;
                        write_bytes = bytes;
                        cpu_samples.push(cpu_ns as f64);
                        if let Some(value) = gpu_ns { gpu_samples.push(value); }
                        final_consistency = Some(consistency);
                    }
                    let consistency = final_consistency.context("compiler-selected replay produced no sample")?;
                    anyhow::ensure!(consistency.self_consistent, "compiler-selected report row lost self-consistency");
                    rows.push(ReplayMatrixRow {
                        workload_id: workload_id.clone(),
                        mode: mode.id().to_string(),
                        warmup_iterations,
                        sample_iterations,
                        submitted_tile_count: final_stats.tile_count,
                        submitted_glyph_draw_count: final_stats.glyph_draw_count,
                        submitted_glyph_instance_count: final_stats.glyph_instance_count,
                        expected_write_bytes: write_bytes,
                        gpu_elapsed_ns: if gpu_samples.is_empty() { None } else { Some(Self::summarize_samples(gpu_samples)) },
                        cpu_event_to_submit_ns: Self::summarize_samples(cpu_samples),
                        compiler_selected: Some(consistency),
                    });
                } else {
                    for _ in 0..warmup_iterations { let _ = self.replay_once(mode, &workload_id, false)?; }
                    let mut gpu_samples = Vec::new();
                    let mut cpu_samples = Vec::with_capacity(sample_iterations);
                    let mut final_stats = SubmittedTileStats::default();
                    let mut write_bytes = 0usize;
                    for _ in 0..sample_iterations {
                        let (stats, gpu_ns, cpu_ns, bytes) = self.replay_once(mode, &workload_id, true)?;
                        final_stats = stats;
                        write_bytes = bytes;
                        cpu_samples.push(cpu_ns as f64);
                        if let Some(value) = gpu_ns { gpu_samples.push(value); }
                    }
                    rows.push(ReplayMatrixRow {
                        workload_id: workload_id.clone(),
                        mode: mode.id().to_string(),
                        warmup_iterations,
                        sample_iterations,
                        submitted_tile_count: final_stats.tile_count,
                        submitted_glyph_draw_count: final_stats.glyph_draw_count,
                        submitted_glyph_instance_count: final_stats.glyph_instance_count,
                        expected_write_bytes: write_bytes,
                        gpu_elapsed_ns: if gpu_samples.is_empty() { None } else { Some(Self::summarize_samples(gpu_samples)) },
                        cpu_event_to_submit_ns: Self::summarize_samples(cpu_samples),
                        compiler_selected: None,
                    });
                }
            }
        }
        let report = ReplayMatrixReport {
            schema: "noir-wgpu-replay-matrix-v2".to_string(),
            renderer: "full-redraw / packet-aware / action-aware / coalesced / compiler-selected".to_string(),
            profile_id: self.scene.render_schedules.first().map(|schedule| schedule.profile_id.clone()).unwrap_or_else(|| "none".to_string()),
            adapter_name: self.adapter_name.clone(),
            backend: self.backend_name.clone(),
            timestamp_query_supported: self.gpu_timer.is_some(),
            timestamp_period_ns: self.gpu_timer.as_ref().map(|timer| timer.timestamp_period_ns),
            warmup_iterations,
            sample_iterations,
            rows,
        };
        fs::write(report_path, serde_json::to_string_pretty(&report)? + "\n")
            .with_context(|| format!("write replay matrix report {report_path}"))?;
        println!("replay matrix report: {report_path}");
        Ok(())
    }

    fn write_calibration_manifest(&self, replay_report_path: &str, manifest_path: &str) -> Result<()> {
        let report_text = fs::read_to_string(replay_report_path)
            .with_context(|| format!("read replay report {replay_report_path}"))?;
        let report: ReplayMatrixReport = serde_json::from_str(&report_text)
            .with_context(|| format!("parse replay report {replay_report_path}"))?;
        anyhow::ensure!(report.schema == "noir-wgpu-replay-matrix-v2", "manifest requires replay matrix v2");
        let mut compiler_selected = Vec::new();
        for row in report.rows.iter().filter(|row| row.mode == "compiler-selected") {
            let consistency = row.compiler_selected.as_ref()
                .with_context(|| format!("compiler-selected row {} lacks consistency payload", row.workload_id))?;
            anyhow::ensure!(consistency.self_consistent, "compiler-selected row {} is not self-consistent", row.workload_id);
            let gpu = row.gpu_elapsed_ns.as_ref()
                .with_context(|| format!("compiler-selected row {} lacks GPU timestamp samples", row.workload_id))?;
            compiler_selected.push(CalibrationManifestCase {
                batch_id: row.workload_id.clone(),
                strategy_id: consistency.actual_executor.clone(),
                tile_mask_hex: consistency.observed_tile_mask_hex.clone(),
                tile_count: row.submitted_tile_count,
                glyph_draw_count: row.submitted_glyph_draw_count,
                glyph_instance_count: row.submitted_glyph_instance_count,
                winner_write_bytes: row.expected_write_bytes,
                gpu_median_ns: gpu.median_ns,
                gpu_p95_ns: gpu.p95_ns,
            });
        }
        anyhow::ensure!(!compiler_selected.is_empty(), "calibration manifest requires compiler-selected rows");
        compiler_selected.sort_by(|left, right| left.batch_id.cmp(&right.batch_id));
        let manifest = CalibrationManifest {
            schema: "noir-calibration-manifest-v1".to_string(),
            profile_id: report.profile_id,
            scene_fingerprint_fnv1a64: self.scene_fingerprint_fnv1a64.clone(),
            source_fingerprint_fnv1a64: self.source_fingerprint_fnv1a64.clone(),
            replay_report_fingerprint_fnv1a64: fnv1a64_hex(report_text.as_bytes()),
            replay_schema: report.schema,
            renderer: report.renderer,
            adapter_name: report.adapter_name,
            backend: report.backend,
            timestamp_query_supported: report.timestamp_query_supported,
            timestamp_period_ns: report.timestamp_period_ns,
            warmup_iterations: report.warmup_iterations,
            sample_iterations: report.sample_iterations,
            compiler_selected,
        };
        fs::write(manifest_path, serde_json::to_string_pretty(&manifest)? + "\n")
            .with_context(|| format!("write calibration manifest {manifest_path}"))?;
        println!("calibration manifest: {manifest_path}");
        Ok(())
    }

    fn run_benchmark_matrix(&mut self, report_path: &str) -> Result<()> {
        // Benchmark cases are the compiler-emitted activate batches. The ID ordering is fixed
        // before execution so the report is reproducible even though the backing map is hashed.
        let mut case_ids: Vec<String> = self.coalesced_batches.keys()
            .filter(|id| id.starts_with("coalesced-activate-"))
            .cloned().collect();
        case_ids.sort();
        anyhow::ensure!(!case_ids.is_empty(), "compiler emitted no activate batch benchmark cases");
        let mut cases = Vec::with_capacity(case_ids.len());
        for case_id in case_ids {
            let batch = self.coalesced_batches.get(&case_id).cloned()
                .context("benchmark batch disappeared after compiler validation")?;
            self.pending_render.clear();
            self.canvas_dirty = false;
            let expected_stats = self.expected_selected_tile_stats(batch.tile_mask);
            let started = Instant::now();
            self.execute_coalesced_batch(&case_id);
            let request = self.pending_render.pop().context("benchmark batch produced no RenderRequest")?;
            let observed_mask = request.tile_mask;
            let (observed_stats, gpu_elapsed_ns, cpu_event_to_submit_ns) =
                self.redraw_selected_tiles(request, true, Some(started));
            let winner_write_bytes: usize = batch.winner_writes.iter().map(|write| write.byte_length).sum();
            let expectations_match = observed_mask == batch.tile_mask
                && observed_stats.tile_count == expected_stats.tile_count
                && observed_stats.glyph_draw_count == expected_stats.glyph_draw_count
                && observed_stats.glyph_instance_count == expected_stats.glyph_instance_count;
            anyhow::ensure!(expectations_match, "benchmark case {} diverged from compiler tile/placement contract", case_id);
            println!("benchmark case={case_id} tiles={} glyph_draws={} glyph_instances={} cpu_submit_ns={} gpu_ns={}",
                     observed_stats.tile_count, observed_stats.glyph_draw_count, observed_stats.glyph_instance_count,
                     cpu_event_to_submit_ns.unwrap_or(0), gpu_elapsed_ns.map(|value| format!("{value:.1}")).unwrap_or_else(|| "unsupported".to_string()));
            cases.push(BenchmarkCaseReport {
                id: case_id,
                execution_order: batch.execution_refs.iter().map(|task_ref| match task_ref {
                    CompiledTaskRef::Action(index) => format!("action:{index}"),
                    CompiledTaskRef::Transaction(index) => format!("transaction:{index}"),
                    CompiledTaskRef::Transient(index) => format!("transient:{index}"),
                }).collect(),
                expected_tile_mask_hex: format!("0x{:016x}", batch.tile_mask),
                observed_tile_mask_hex: format!("0x{:016x}", observed_mask),
                expected_winner_write_count: batch.winner_writes.len(),
                expected_winner_write_bytes: winner_write_bytes,
                submitted_tile_count: observed_stats.tile_count,
                submitted_glyph_draw_count: observed_stats.glyph_draw_count,
                submitted_glyph_instance_count: observed_stats.glyph_instance_count,
                cpu_event_to_submit_ns: cpu_event_to_submit_ns.unwrap_or(0),
                gpu_elapsed_ns,
                expectations_match,
            });
        }
        let report = BenchmarkReport {
            schema: "noir-wgpu-benchmark-v1".to_string(),
            renderer: "coalesced-batch-executor + action-aware tile + placement renderer".to_string(),
            profile_id: self.scene.render_schedules.first().map(|schedule| schedule.profile_id.clone()).unwrap_or_else(|| "none".to_string()),
            adapter_name: self.adapter_name.clone(),
            backend: self.backend_name.clone(),
            timestamp_query_supported: self.gpu_timer.is_some(),
            timestamp_period_ns: self.gpu_timer.as_ref().map(|timer| timer.timestamp_period_ns),
            cases,
        };
        fs::write(report_path, serde_json::to_string_pretty(&report)? + "\n")
            .with_context(|| format!("write benchmark report {report_path}"))?;
        println!("benchmark report: {report_path}");
        Ok(())
    }

    fn measure_fusion_executor(&mut self, batch_id: &str, fused: bool, measure_gpu: bool) -> Result<FusionExecutorMeasurement> {
        self.pending_render.clear();
        self.canvas_dirty = false;
        let started = Instant::now();
        let (batch, fused_slot) = self.apply_compiler_batch_writes(batch_id)
            .with_context(|| format!("fusion benchmark batch {batch_id} is missing"))?;
        let requests: Vec<CompiledFusionBaselineRequest> = if fused {
            vec![CompiledFusionBaselineRequest {
                tile_mask: batch.tile_mask,
                packet_worklist_index: fused_slot,
            }]
        } else {
            anyhow::ensure!(!batch.fusion_baseline_requests.is_empty(),
                            "fusion benchmark batch {} has no compiler baseline request plan", batch.id);
            batch.fusion_baseline_requests.clone()
        };
        let mut observed_mask = 0u64;
        let mut stats = SubmittedTileStats::default();
        let mut gpu_elapsed_ns = Some(0.0f64);
        let mut cpu_event_to_submit_ns = 0u128;
        for request in &requests {
            observed_mask |= request.tile_mask;
            let render = RenderRequest::with_strategy(request.tile_mask, batch.strategy, request.packet_worklist_index);
            let (request_stats, request_gpu, request_cpu) = self.redraw_selected_tiles(render, measure_gpu, Some(started));
            stats.tile_count += request_stats.tile_count;
            stats.glyph_draw_count += request_stats.glyph_draw_count;
            stats.glyph_instance_count += request_stats.glyph_instance_count;
            cpu_event_to_submit_ns = request_cpu.unwrap_or(cpu_event_to_submit_ns);
            gpu_elapsed_ns = match (gpu_elapsed_ns, request_gpu) {
                (Some(total), Some(value)) => Some(total + value),
                _ => None,
            };
        }
        Ok(FusionExecutorMeasurement {
            request_count: requests.len(),
            packet_activity_dispatch_count: requests.len(),
            queue_submit_count: requests.len(),
            tile_mask_hex: format!("0x{:016x}", observed_mask),
            submitted_tile_count: stats.tile_count,
            submitted_glyph_draw_count: stats.glyph_draw_count,
            submitted_glyph_instance_count: stats.glyph_instance_count,
            cpu_event_to_submit_ns,
            gpu_elapsed_ns,
        })
    }

    fn run_fusion_benchmark(&mut self, report_path: &str) -> Result<()> {
        let mut case_ids: Vec<String> = self.coalesced_batches.iter()
            .filter(|(_, batch)| !batch.fusion_baseline_requests.is_empty())
            .map(|(id, _)| id.clone()).collect();
        case_ids.sort();
        anyhow::ensure!(!case_ids.is_empty(), "scene has no compiler-proved multi-request fusion benchmark batches");
        let mut cases = Vec::with_capacity(case_ids.len());
        for case_id in case_ids {
            let batch = self.coalesced_batches.get(&case_id).cloned()
                .context("fusion benchmark batch disappeared after validation")?;
            let expected_stats = self.expected_selected_tile_stats(batch.tile_mask);
            // Warm both paths before recording. This avoids assigning lazy pipeline/driver
            // initialization to the first (three-request) executor in a fresh process.
            for _ in 0..2 {
                let _ = self.measure_fusion_executor(&case_id, false, false)?;
                let _ = self.measure_fusion_executor(&case_id, true, false)?;
            }
            if self.gpu_timer.is_some() {
                let _ = self.measure_fusion_executor(&case_id, false, true)?;
                let _ = self.measure_fusion_executor(&case_id, true, true)?;
            }
            // CPU submit timing must not include synchronous timestamp readback. Measure it
            // without GPU queries, then obtain GPU totals in a separate identical executor pass.
            let mut baseline = self.measure_fusion_executor(&case_id, false, false)?;
            let baseline_gpu = self.measure_fusion_executor(&case_id, false, true)?;
            baseline.gpu_elapsed_ns = baseline_gpu.gpu_elapsed_ns;
            let mut fused = self.measure_fusion_executor(&case_id, true, false)?;
            let fused_gpu = self.measure_fusion_executor(&case_id, true, true)?;
            fused.gpu_elapsed_ns = fused_gpu.gpu_elapsed_ns;
            let expectations_match = baseline.tile_mask_hex == format!("0x{:016x}", batch.tile_mask)
                && fused.tile_mask_hex == format!("0x{:016x}", batch.tile_mask)
                && baseline.submitted_tile_count == expected_stats.tile_count
                && fused.submitted_tile_count == expected_stats.tile_count
                && baseline.submitted_glyph_draw_count == expected_stats.glyph_draw_count
                && fused.submitted_glyph_draw_count == expected_stats.glyph_draw_count
                && baseline.submitted_glyph_instance_count == expected_stats.glyph_instance_count
                && fused.submitted_glyph_instance_count == expected_stats.glyph_instance_count
                && baseline.request_count == batch.fusion_baseline_requests.len()
                && fused.request_count == 1;
            anyhow::ensure!(expectations_match, "fusion benchmark case {} diverged from compiler proof", case_id);
            println!("fusion-benchmark case={} baseline=requests:{} dispatches:{} submits:{} fused=requests:{} dispatches:{} submits:{}",
                     case_id, baseline.request_count, baseline.packet_activity_dispatch_count, baseline.queue_submit_count,
                     fused.request_count, fused.packet_activity_dispatch_count, fused.queue_submit_count);
            cases.push(FusionBenchmarkCaseReport {
                id: case_id,
                member_worklist_indices: batch.composite_worklist_member_indices.clone(),
                fused_worklist_index: batch.composite_worklist_index,
                exact_packet_union: batch.composite_worklist_packet_indices.clone(),
                expectations_match,
                baseline,
                fused,
            });
        }
        let report = FusionBenchmarkReport {
            schema: "noir-fusion-benchmark-v1".to_string(),
            renderer: "compiler-proved three-request baseline vs fused RenderRequest".to_string(),
            profile_id: self.scene.render_schedules.first().map(|schedule| schedule.profile_id.clone()).unwrap_or_else(|| "none".to_string()),
            adapter_name: self.adapter_name.clone(), backend: self.backend_name.clone(),
            timestamp_query_supported: self.gpu_timer.is_some(),
            timestamp_period_ns: self.gpu_timer.as_ref().map(|timer| timer.timestamp_period_ns),
            cases,
        };
        fs::write(report_path, serde_json::to_string_pretty(&report)? + "\n")
            .with_context(|| format!("write fusion benchmark report {report_path}"))?;
        println!("fusion benchmark report: {report_path}");
        Ok(())
    }

    fn present(&mut self) -> Result<()> {
        if self.canvas_dirty {
            self.redraw_canvas_requests();
        }
        let output=match self.surface.get_current_texture(){wgpu::CurrentSurfaceTexture::Success(v)|wgpu::CurrentSurfaceTexture::Suboptimal(v)=>v,wgpu::CurrentSurfaceTexture::Lost|wgpu::CurrentSurfaceTexture::Outdated=>{self.surface.configure(&self.device,&self.config);return Ok(())},wgpu::CurrentSurfaceTexture::Timeout|wgpu::CurrentSurfaceTexture::Occluded=>return Ok(()),wgpu::CurrentSurfaceTexture::Validation=>return Err(anyhow::anyhow!("wgpu surface validation failure"))};
        let view=output.texture.create_view(&wgpu::TextureViewDescriptor::default()); let mut encoder=self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor{label:Some("noir-present")});
        { let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor{label:Some("noir-present-pass"),color_attachments:&[Some(wgpu::RenderPassColorAttachment{view:&view,resolve_target:None,depth_slice:None,ops:wgpu::Operations{load:wgpu::LoadOp::Clear(wgpu::Color::BLACK),store:wgpu::StoreOp::Store}})],depth_stencil_attachment:None,timestamp_writes:None,occlusion_query_set: None, multiview_mask: None}); pass.set_pipeline(&self.blit_pipeline); pass.set_bind_group(0,&self.blit_bind_group,&[]); pass.draw(0..3,0..1); }
        self.queue.submit(Some(encoder.finish())); self.queue.present(output); Ok(())
    }
    fn resize(&mut self,size:PhysicalSize<u32>){if size.width==0||size.height==0{return};self.size=size;self.config.width=size.width;self.config.height=size.height;self.surface.configure(&self.device,&self.config);}
}

fn fnv1a64_hex(bytes: &[u8]) -> String {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in bytes { hash = (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3); }
    format!("fnv1a64:{hash:016x}")
}

fn relative_drift(observed: f64, frozen: f64) -> f64 {
    if frozen <= 0.0 { f64::INFINITY } else { (observed - frozen).abs() / frozen }
}

fn write_freshness_diagnostic(
    manifest_path: &str,
    registry_path: &str,
    scene_path: &str,
    replay_report_path: &str,
    output_path: &str,
    relative_drift_threshold: f64,
    minimum_samples: usize,
) -> Result<()> {
    let manifest_text = fs::read_to_string(manifest_path).with_context(|| format!("read manifest {manifest_path}"))?;
    let manifest: CalibrationManifest = serde_json::from_str(&manifest_text).with_context(|| format!("parse manifest {manifest_path}"))?;
    let registry_text = fs::read_to_string(registry_path).with_context(|| format!("read registry {registry_path}"))?;
    let registry: FreshnessRegistry = serde_json::from_str(&registry_text).with_context(|| format!("parse registry {registry_path}"))?;
    let replay_text = fs::read_to_string(replay_report_path).with_context(|| format!("read replay report {replay_report_path}"))?;
    let replay: ReplayMatrixReport = serde_json::from_str(&replay_text).with_context(|| format!("parse replay report {replay_report_path}"))?;
    let scene_bytes = fs::read(scene_path).with_context(|| format!("read scene {scene_path}"))?;
    let scene: Scene = serde_json::from_slice(&scene_bytes).with_context(|| format!("parse Scene attestation {scene_path}"))?;
    let source_fingerprint = scene.build_attestation.as_ref()
        .filter(|attestation| attestation.schema == "noir-build-attestation-v1")
        .map(|attestation| attestation.source_fingerprint_fnv1a64.clone())
        .unwrap_or_else(|| "unattested".to_string());
    let mut checks = Vec::new();
    let mut identity_ok = true;
    let mut check = |name: &str, passed: bool, detail: String| {
        if !passed { identity_ok = false; }
        checks.push(FreshnessCheck { name: name.to_string(), passed, detail });
    };
    check("manifest-schema", manifest.schema == "noir-calibration-manifest-v1", manifest.schema.clone());
    check("registry-version", registry.registry_version == 2, registry.registry_version.to_string());
    check("source-fingerprint", source_fingerprint == manifest.source_fingerprint_fnv1a64,
          format!("expected={}, observed={}", manifest.source_fingerprint_fnv1a64, source_fingerprint));
    // Output JSON changes when proof metadata evolves; it is retained for forensics but cannot be
    // the admission identity because source/ABI attestation is the stable calibrated contract.
    check("scene-output-fingerprint-informational", true,
          format!("calibrated={}, current={}", manifest.scene_fingerprint_fnv1a64, fnv1a64_hex(&scene_bytes)));
    check("replay-fingerprint", fnv1a64_hex(replay_text.as_bytes()) == manifest.replay_report_fingerprint_fnv1a64,
          format!("expected={}, observed={}", manifest.replay_report_fingerprint_fnv1a64, fnv1a64_hex(replay_text.as_bytes())));
    check("replay-schema", replay.schema == manifest.replay_schema, format!("manifest={}, replay={}", manifest.replay_schema, replay.schema));
    check("replay-profile", replay.profile_id == manifest.profile_id, format!("manifest={}, replay={}", manifest.profile_id, replay.profile_id));
    check("adapter", replay.adapter_name == manifest.adapter_name && replay.backend == manifest.backend,
          format!("manifest={}/{} replay={}/{}", manifest.backend, manifest.adapter_name, replay.backend, replay.adapter_name));
    check("timestamp", replay.timestamp_query_supported && manifest.timestamp_query_supported
          && replay.timestamp_period_ns == manifest.timestamp_period_ns,
          format!("manifest={:?} replay={:?}", manifest.timestamp_period_ns, replay.timestamp_period_ns));
    let profile = registry.profiles.iter().find(|profile| profile.profile_id == manifest.profile_id);
    check("profile-present", profile.is_some(), manifest.profile_id.clone());
    let mut comparisons = Vec::new();
    let mut cost_ok = true;
    if let Some(profile) = profile {
        check("profile-matcher", profile.matcher.backend == manifest.backend && profile.matcher.adapter == manifest.adapter_name
              && profile.matcher.width == WIDTH && profile.matcher.height == HEIGHT,
              format!("registry={}/{} {}x{} manifest={}/{} {}x{}", profile.matcher.backend, profile.matcher.adapter, profile.matcher.width, profile.matcher.height, manifest.backend, manifest.adapter_name, WIDTH, HEIGHT));
        check("profile-timestamp", profile.timestamp_supported && (profile.timestamp_period_ns - manifest.timestamp_period_ns.unwrap_or(-1.0) as f64).abs() < f64::EPSILON,
              format!("registry={} manifest={:?}", profile.timestamp_period_ns, manifest.timestamp_period_ns));
        check("profile-replay-schema", profile.replay_strategy_costs.schema == "noir-wgpu-replay-matrix-v1"
              && profile.replay_strategy_costs.semantic_group == "complete-activate-v1"
              && profile.replay_strategy_costs.selection_metric == "gpu_median_ns",
              format!("{}/{}/{}", profile.replay_strategy_costs.schema, profile.replay_strategy_costs.semantic_group, profile.replay_strategy_costs.selection_metric));
        for observed in &manifest.compiler_selected {
            let frozen = profile.replay_strategy_costs.batches.iter().find(|batch| batch.batch_id == observed.batch_id)
                .and_then(|batch| batch.candidates.iter().find(|candidate| candidate.strategy_id == observed.strategy_id));
            let Some(frozen) = frozen else {
                cost_ok = false;
                comparisons.push(FreshnessComparison { batch_id: observed.batch_id.clone(), strategy_id: observed.strategy_id.clone(), observed_gpu_median_ns: observed.gpu_median_ns, profile_gpu_median_ns: 0.0, median_relative_drift: f64::INFINITY, observed_gpu_p95_ns: observed.gpu_p95_ns, profile_gpu_p95_ns: 0.0, p95_relative_drift: f64::INFINITY, work_contract_matches: false });
                continue;
            };
            let work_contract_matches = observed.tile_count == frozen.tile_count
                && observed.glyph_draw_count == frozen.glyph_draw_count
                && observed.glyph_instance_count == frozen.glyph_instance_count
                && observed.winner_write_bytes == frozen.winner_write_bytes;
            let median_relative_drift = relative_drift(observed.gpu_median_ns, frozen.gpu_median_ns);
            let p95_relative_drift = relative_drift(observed.gpu_p95_ns, frozen.gpu_p95_ns);
            if !work_contract_matches || median_relative_drift > relative_drift_threshold || p95_relative_drift > relative_drift_threshold { cost_ok = false; }
            comparisons.push(FreshnessComparison { batch_id: observed.batch_id.clone(), strategy_id: observed.strategy_id.clone(), observed_gpu_median_ns: observed.gpu_median_ns, profile_gpu_median_ns: frozen.gpu_median_ns, median_relative_drift, observed_gpu_p95_ns: observed.gpu_p95_ns, profile_gpu_p95_ns: frozen.gpu_p95_ns, p95_relative_drift, work_contract_matches });
        }
    }
    let adequate_samples = manifest.sample_iterations >= minimum_samples;
    checks.push(FreshnessCheck { name: "minimum-samples".to_string(), passed: adequate_samples, detail: format!("required={minimum_samples}, observed={}", manifest.sample_iterations) });
    let status = if !identity_ok { "stale" }
        else if !adequate_samples { "inconclusive" }
        else if !cost_ok { "stale" }
        else { "fresh" };
    let diagnostic = FreshnessDiagnostic {
        schema: "noir-profile-freshness-v1".to_string(),
        status: status.to_string(),
        policy: "diagnostic-only; runtime strategy_id is immutable".to_string(),
        relative_drift_threshold,
        minimum_samples,
        checks,
        comparisons,
        note: "This gate never selects or changes a renderer strategy. It reports whether the offline calibration artifact remains compatible with the current Scene and replay evidence.".to_string(),
    };
    fs::write(output_path, serde_json::to_string_pretty(&diagnostic)? + "\n")
        .with_context(|| format!("write freshness diagnostic {output_path}"))?;
    println!("freshness gate: status={status} report={output_path}");
    Ok(())
}

fn make_rounded_surface_resources(device: &wgpu::Device, metadata: &[GpuRoundedSurfaceMeta]) -> (wgpu::BindGroupLayout, wgpu::Buffer, wgpu::BindGroup) {
    let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("noir-rounded-surface-layout"),
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0, visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None },
            count: None,
        }],
    });
    let buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("noir-rounded-surface-metadata"), contents: bytemuck::cast_slice(metadata), usage: wgpu::BufferUsages::STORAGE,
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("noir-rounded-surface-bind-group"), layout: &layout,
        entries: &[wgpu::BindGroupEntry { binding: 0, resource: buffer.as_entire_binding() }],
    });
    (layout, buffer, bind_group)
}

fn make_shadow_surface_resources(device: &wgpu::Device, metadata: &[GpuShadowSurfaceMeta]) -> (wgpu::BindGroupLayout, wgpu::Buffer, wgpu::BindGroup) {
    // wgpu storage bindings may not be zero-sized. A disabled bench Scene receives
    // one all-zero sentinel that is never drawn because shadow_instance_count is zero.
    let upload = if metadata.is_empty() { vec![GpuShadowSurfaceMeta::zeroed()] } else { metadata.to_vec() };
    let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("noir-shadow-surface-layout"),
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0, visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None },
            count: None,
        }],
    });
    let buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("noir-shadow-surface-metadata"), contents: bytemuck::cast_slice(&upload), usage: wgpu::BufferUsages::STORAGE,
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("noir-shadow-surface-bind-group"), layout: &layout,
        entries: &[wgpu::BindGroupEntry { binding: 0, resource: buffer.as_entire_binding() }],
    });
    (layout, buffer, bind_group)
}

fn make_shadow_pipeline(device:&wgpu::Device, format:wgpu::TextureFormat, shadow_surface_layout: &wgpu::BindGroupLayout)->wgpu::RenderPipeline{
 let shader=device.create_shader_module(wgpu::ShaderModuleDescriptor{label:Some("noir-shadow-sdf"),source:wgpu::ShaderSource::Wgsl(include_str!("../host_shadow.wgsl").into())}); let layout=device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor{label:Some("noir-shadow-layout"),bind_group_layouts:&[Some(shadow_surface_layout)],immediate_size:0});
 device.create_render_pipeline(&wgpu::RenderPipelineDescriptor{label:Some("noir-shadow-pipeline"),layout:Some(&layout),vertex:wgpu::VertexState{module:&shader,entry_point:Some("vs_main"),buffers:&[Some(unit_layout()),Some(static_instance_layout())],compilation_options:Default::default()},fragment:Some(wgpu::FragmentState{module:&shader,entry_point:Some("fs_main"),targets:&[Some(wgpu::ColorTargetState{format,blend:Some(wgpu::BlendState::ALPHA_BLENDING),write_mask:wgpu::ColorWrites::ALL})],compilation_options:Default::default()}),primitive:wgpu::PrimitiveState::default(),depth_stencil:None,multisample:wgpu::MultisampleState::default(),multiview_mask:None,cache:None})
}

fn make_focus_ring_resources(device: &wgpu::Device, metadata: &[GpuFocusRingMeta]) -> (wgpu::BindGroupLayout, wgpu::Buffer, wgpu::BindGroup) {
    // A disabled Scene needs a nonzero storage binding even though no focus-ring draw is issued.
    let upload = if metadata.is_empty() { vec![GpuFocusRingMeta::zeroed()] } else { metadata.to_vec() };
    let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("noir-focus-ring-layout"),
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None },
            count: None,
        }],
    });
    let buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("noir-focus-ring-metadata"),
        contents: bytemuck::cast_slice(&upload),
        usage: wgpu::BufferUsages::STORAGE,
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("noir-focus-ring-bind-group"),
        layout: &layout,
        entries: &[wgpu::BindGroupEntry { binding: 0, resource: buffer.as_entire_binding() }],
    });
    (layout, buffer, bind_group)
}

fn make_focus_ring_pipeline(device: &wgpu::Device, format: wgpu::TextureFormat, focus_ring_layout: &wgpu::BindGroupLayout) -> wgpu::RenderPipeline {
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("noir-focus-ring-sdf"),
        source: wgpu::ShaderSource::Wgsl(include_str!("../host_focus_ring.wgsl").into()),
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("noir-focus-ring-pipeline-layout"),
        bind_group_layouts: &[Some(focus_ring_layout)],
        immediate_size: 0,
    });
    device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("noir-focus-ring-pipeline"),
        layout: Some(&layout),
        vertex: wgpu::VertexState {
            module: &shader, entry_point: Some("vs_main"),
            buffers: &[Some(unit_layout()), Some(static_instance_layout())], compilation_options: Default::default(),
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader, entry_point: Some("fs_main"),
            targets: &[Some(wgpu::ColorTargetState { format, blend: Some(wgpu::BlendState::ALPHA_BLENDING), write_mask: wgpu::ColorWrites::ALL })],
            compilation_options: Default::default(),
        }),
        primitive: wgpu::PrimitiveState::default(), depth_stencil: None,
        multisample: wgpu::MultisampleState::default(), multiview_mask: None, cache: None,
    })
}

fn make_static_pipeline(device:&wgpu::Device, format:wgpu::TextureFormat, rounded_surface_layout: &wgpu::BindGroupLayout)->wgpu::RenderPipeline{
 let shader=device.create_shader_module(wgpu::ShaderModuleDescriptor{label:Some("noir-static-quad"),source:wgpu::ShaderSource::Wgsl(include_str!("../host_quad.wgsl").into())}); let layout=device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor{label:Some("noir-static-layout"),bind_group_layouts:&[Some(rounded_surface_layout)],immediate_size:0});
 device.create_render_pipeline(&wgpu::RenderPipelineDescriptor{label:Some("noir-static-pipeline"),layout:Some(&layout),vertex:wgpu::VertexState{module:&shader,entry_point:Some("vs_main"),buffers:&[Some(unit_layout()),Some(static_instance_layout())],compilation_options:Default::default()},fragment:Some(wgpu::FragmentState{module:&shader,entry_point:Some("fs_main"),targets:&[Some(wgpu::ColorTargetState{format,blend:Some(wgpu::BlendState::ALPHA_BLENDING),write_mask:wgpu::ColorWrites::ALL})],compilation_options:Default::default()}),primitive:wgpu::PrimitiveState::default(),depth_stencil:None,multisample:wgpu::MultisampleState::default(),multiview_mask:None,cache:None})
}
fn dispatch_packet_activity<'a>(pass: &mut wgpu::ComputePass<'a>, activity: &'a PacketActivityResources, worklist_index: usize) {
    let dynamic_offset = (worklist_index as u32)
        .checked_mul(activity.worklist_stride)
        .expect("compiler worklist differential offset overflow");
    pass.set_pipeline(&activity.pipeline);
    pass.set_bind_group(0, &activity.bind_group, &[dynamic_offset]);
    pass.dispatch_workgroups(activity.packet_count, 1, 1);
}

fn readback_bytes(device: &wgpu::Device, buffer: &wgpu::Buffer, size: u64) -> Result<Vec<u8>> {
    let slice = buffer.slice(..size);
    let (sender, receiver) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| { let _ = sender.send(result); });
    device.poll(wgpu::PollType::wait_indefinitely()).context("packet differential device poll failed")?;
    receiver.recv().context("packet differential readback channel closed")??;
    let bytes = slice.get_mapped_range().context("read packet activity mapped range")?.to_vec();
    let _ = slice;
    buffer.unmap();
    Ok(bytes)
}

fn run_packet_activity_differential(device: &wgpu::Device, queue: &wgpu::Queue, selected: &PacketActivityResources, reference: &PacketActivityResources) -> Result<()> {
    anyhow::ensure!(selected.packet_count == reference.packet_count, "packet differential variants disagree on packet count");
    let activity_size = selected.packet_count as u64 * 4;
    let indirect_size = selected.packet_count as u64 * 16;
    let make_readback = |label| device.create_buffer(&wgpu::BufferDescriptor { label: Some(label), size: activity_size.max(indirect_size), usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ, mapped_at_creation: false });
    let selected_activity = make_readback("noir-packet-diff-selected-activity");
    let reference_activity = make_readback("noir-packet-diff-reference-activity");
    let selected_indirect = make_readback("noir-packet-diff-selected-indirect");
    let reference_indirect = make_readback("noir-packet-diff-reference-indirect");
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("noir-packet-activity-differential") });
    { let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor { label: Some("noir-packet-diff-reference-pass"), timestamp_writes: None }); dispatch_packet_activity(&mut pass, reference, 0); }
    { let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor { label: Some("noir-packet-diff-selected-pass"), timestamp_writes: None }); dispatch_packet_activity(&mut pass, selected, 0); }
    encoder.copy_buffer_to_buffer(&reference.activity_buffer, 0, &reference_activity, 0, activity_size);
    encoder.copy_buffer_to_buffer(&selected.activity_buffer, 0, &selected_activity, 0, activity_size);
    encoder.copy_buffer_to_buffer(&reference.indirect_buffer, 0, &reference_indirect, 0, indirect_size);
    encoder.copy_buffer_to_buffer(&selected.indirect_buffer, 0, &selected_indirect, 0, indirect_size);
    queue.submit(Some(encoder.finish()));
    let selected_activity_bytes = readback_bytes(device, &selected_activity, activity_size)?;
    let reference_activity_bytes = readback_bytes(device, &reference_activity, activity_size)?;
    let selected_indirect_bytes = readback_bytes(device, &selected_indirect, indirect_size)?;
    let reference_indirect_bytes = readback_bytes(device, &reference_indirect, indirect_size)?;
    anyhow::ensure!(selected_activity_bytes == reference_activity_bytes, "packet activity differential mismatch");
    anyhow::ensure!(selected_indirect_bytes == reference_indirect_bytes, "packet indirect differential mismatch");
    println!("packet-activity-differential: selected={:?} reference={:?} packets={} activity+indirect=equal", selected.variant, reference.variant, selected.packet_count);

    Ok(())
}

fn make_packet_activity_resources(device: &wgpu::Device, glyph_buffer: &wgpu::Buffer, packets: &[CompiledSubgroupPacket], worklists: &[CompiledPacketWorklist], variant: PacketActivityVariant) -> Option<PacketActivityResources> {
    if packets.is_empty() { return None; }
    let descriptors: Vec<GpuPacketDescriptor> = packets.iter().map(|packet| GpuPacketDescriptor {
        first_placement: packet.first_placement,
        lane_count: packet.lane_count,
        active_lane_mask: packet.active_lane_mask,
        dynamic: u32::from(packet.dynamic),
    }).collect();
    let initial_indirect: Vec<GpuDrawIndirect> = packets.iter().map(|packet| GpuDrawIndirect {
        vertex_count: 6, instance_count: 0, first_vertex: 0, first_instance: packet.first_placement,
    }).collect();
    let descriptor_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("noir-subgroup-packet-descriptors"), contents: bytemuck::cast_slice(&descriptors), usage: wgpu::BufferUsages::STORAGE,
    });
    // WGSL consumes one 160-byte GpuPacketWorklist. Dynamic uniform offsets must
    // honour the adapter limit (normally 256 bytes), so each compiler list owns an
    // alignment-padded immutable slot in one GPU-resident table.
    let payload_size = std::mem::size_of::<GpuPacketWorklist>() as u64;
    let alignment = device.limits().min_uniform_buffer_offset_alignment.max(1) as u64;
    let worklist_stride = ((payload_size + alignment - 1) / alignment) * alignment;
    let mut worklist_bytes = vec![0u8; worklist_stride as usize * worklists.len().max(1)];
    for worklist in worklists {
        let offset = worklist.index * worklist_stride as usize;
        let payload = gpu_packet_worklist(&worklist.packet_indices);
        worklist_bytes[offset..offset + payload_size as usize]
            .copy_from_slice(bytemuck::bytes_of(&payload));
    }
    let worklist_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("noir-compiler-resident-packet-worklists"), contents: &worklist_bytes, usage: wgpu::BufferUsages::UNIFORM,
    });
    let activity_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("noir-subgroup-packet-activity"), size: (packets.len() * std::mem::size_of::<u32>()) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC, mapped_at_creation: false,
    });
    let indirect_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("noir-subgroup-packet-indirect"), contents: bytemuck::cast_slice(&initial_indirect),
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::INDIRECT | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
    });
    let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("noir-subgroup-packet-activity-layout"), entries: &[
            wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 1, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: false }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 3, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: false }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 4, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: true, min_binding_size: std::num::NonZeroU64::new(payload_size) }, count: None },
        ],
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor { label: Some("noir-subgroup-packet-activity-bind"), layout: &bind_group_layout, entries: &[
        wgpu::BindGroupEntry { binding: 0, resource: glyph_buffer.as_entire_binding() },
        wgpu::BindGroupEntry { binding: 1, resource: descriptor_buffer.as_entire_binding() },
        wgpu::BindGroupEntry { binding: 2, resource: activity_buffer.as_entire_binding() },
        wgpu::BindGroupEntry { binding: 3, resource: indirect_buffer.as_entire_binding() },
        wgpu::BindGroupEntry { binding: 4, resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: &worklist_buffer,
            offset: 0,
            size: std::num::NonZeroU64::new(payload_size),
        }) },
    ]});
    let (shader_source, entry_point, label) = match variant {
        PacketActivityVariant::Scalar => (include_str!("../host_packet_activity.wgsl"), "packet_activity", "noir-packet-activity-scalar-shader"),
        PacketActivityVariant::Subgroup => (include_str!("../host_packet_activity_subgroup.wgsl"), "packet_activity_subgroup", "noir-packet-activity-subgroup-shader"),
    };
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some(label), source: wgpu::ShaderSource::Wgsl(shader_source.into()) });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("noir-subgroup-packet-activity-pipeline-layout"), bind_group_layouts: &[Some(&bind_group_layout)], immediate_size: 0 });
    let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor { label: Some("noir-subgroup-packet-activity-pipeline"), layout: Some(&layout), module: &shader, entry_point: Some(entry_point), compilation_options: Default::default(), cache: None });
    println!("compiler resident packet worklist table: lists={} payload_bytes={} stride_bytes={} hot_path_uploads=0", worklists.len(), payload_size, worklist_stride);
    Some(PacketActivityResources { variant, _descriptor_buffer: descriptor_buffer, activity_buffer, _worklist_buffer: worklist_buffer, worklist_stride: worklist_stride as u32, worklist_count: worklists.len() as u32, indirect_buffer, bind_group, pipeline, packet_count: packets.len() as u32 })
}

fn make_canvas_and_blit(device:&wgpu::Device,format:wgpu::TextureFormat,width:u32,height:u32)->(wgpu::Texture,wgpu::TextureView,wgpu::BindGroup,wgpu::RenderPipeline){let canvas=device.create_texture(&wgpu::TextureDescriptor{label:Some("noir-canvas"),size:wgpu::Extent3d{width,height,depth_or_array_layers:1},mip_level_count:1,sample_count:1,dimension:wgpu::TextureDimension::D2,format,usage:wgpu::TextureUsages::RENDER_ATTACHMENT|wgpu::TextureUsages::TEXTURE_BINDING,view_formats:&[]});let view=canvas.create_view(&Default::default());let sampler=device.create_sampler(&wgpu::SamplerDescriptor{mag_filter:wgpu::FilterMode::Nearest,min_filter:wgpu::FilterMode::Nearest,..Default::default()});let shader=device.create_shader_module(wgpu::ShaderModuleDescriptor{label:Some("noir-blit"),source:wgpu::ShaderSource::Wgsl(include_str!("../host_blit.wgsl").into())});let bgl=device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor{label:Some("noir-canvas-bgl"),entries:&[wgpu::BindGroupLayoutEntry{binding:0,visibility:wgpu::ShaderStages::FRAGMENT,ty:wgpu::BindingType::Texture{multisampled:false,view_dimension:wgpu::TextureViewDimension::D2,sample_type:wgpu::TextureSampleType::Float{filterable:true}},count:None},wgpu::BindGroupLayoutEntry{binding:1,visibility:wgpu::ShaderStages::FRAGMENT,ty:wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),count:None}]});let bg=device.create_bind_group(&wgpu::BindGroupDescriptor{label:Some("noir-canvas-bg"),layout:&bgl,entries:&[wgpu::BindGroupEntry{binding:0,resource:wgpu::BindingResource::TextureView(&view)},wgpu::BindGroupEntry{binding:1,resource:wgpu::BindingResource::Sampler(&sampler)}]});let layout=device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor{label:Some("noir-blit-layout"),bind_group_layouts:&[Some(&bgl)],immediate_size:0});let pipe=device.create_render_pipeline(&wgpu::RenderPipelineDescriptor{label:Some("noir-blit-pipe"),layout:Some(&layout),vertex:wgpu::VertexState{module:&shader,entry_point:Some("vs_main"),buffers:&[],compilation_options:Default::default()},fragment:Some(wgpu::FragmentState{module:&shader,entry_point:Some("fs_main"),targets:&[Some(wgpu::ColorTargetState{format,blend:None,write_mask:wgpu::ColorWrites::ALL})],compilation_options:Default::default()}),primitive:wgpu::PrimitiveState::default(),depth_stencil:None,multisample:wgpu::MultisampleState::default(),multiview_mask:None,cache:None});(canvas,view,bg,pipe)}
fn make_text_resources(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    format: wgpu::TextureFormat,
    glyph_buffer: &wgpu::Buffer,
    font_atlases: &[RegisteredFontAtlas],
    dynamic_atlas: Option<&RegisteredDynamicFontAtlas>,
    dynamic_asset: Option<&VerifiedDynamicFontCellAsset>,
) -> Result<(wgpu::BindGroup, wgpu::RenderPipeline)> {
    let legacy_atlas = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("noir-legacy-glyph-atlas-pages"),
        size: wgpu::Extent3d { width: ATLAS_WIDTH, height: ATLAS_HEIGHT, depth_or_array_layers: ATLAS_PAGES },
        mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::R8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    queue.write_texture(
        wgpu::TexelCopyTextureInfo { texture: &legacy_atlas, mip_level: 0, origin: wgpu::Origin3d { x: 0, y: 0, z: 0 }, aspect: wgpu::TextureAspect::All },
        &digit_atlas_pixels(),
        wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(ATLAS_WIDTH), rows_per_image: Some(ATLAS_HEIGHT) },
        wgpu::Extent3d { width: ATLAS_WIDTH, height: ATLAS_HEIGHT, depth_or_array_layers: 1 },
    );
    queue.write_texture(
        wgpu::TexelCopyTextureInfo { texture: &legacy_atlas, mip_level: 0, origin: wgpu::Origin3d { x: 0, y: 0, z: 1 }, aspect: wgpu::TextureAspect::All },
        &ascii_atlas_pixels(),
        wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(ATLAS_WIDTH), rows_per_image: Some(ATLAS_HEIGHT) },
        wgpu::Extent3d { width: ATLAS_WIDTH, height: ATLAS_HEIGHT, depth_or_array_layers: 1 },
    );
    let legacy_view = legacy_atlas.create_view(&wgpu::TextureViewDescriptor { dimension: Some(wgpu::TextureViewDimension::D2Array), ..Default::default() });
    let legacy_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
        label: Some("noir-legacy-glyph-atlas-sampler"), mag_filter: wgpu::FilterMode::Nearest, min_filter: wgpu::FilterMode::Nearest, ..Default::default()
    });

    // Every pipeline has binding 3/4 so page selection remains a compiler-fixed branch.
    // A transparent 1×1 R8 texture makes zero-font-asset legacy Scenes ABI-compatible.
    let fallback_font_texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("noir-fontc-page2-transparent-fallback"),
        size: wgpu::Extent3d { width: 1, height: 1, depth_or_array_layers: 1 },
        mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::R8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    queue.write_texture(
        wgpu::TexelCopyTextureInfo { texture: &fallback_font_texture, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
        &[0],
        wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(1), rows_per_image: Some(1) },
        wgpu::Extent3d { width: 1, height: 1, depth_or_array_layers: 1 },
    );
    let fallback_font_view = fallback_font_texture.create_view(&wgpu::TextureViewDescriptor::default());
    let font_view = font_atlases.iter().find(|atlas| atlas.atlas_page == 2).map(|atlas| &atlas.view).unwrap_or(&fallback_font_view);
    let font_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
        label: Some("noir-fontc-page2-linear-sampler"), mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default()
    });

    let tabular_uvs = dynamic_asset.map(|asset| {
        asset.glyphs.iter().map(|glyph| [
            glyph.x as f32 / 256.0, glyph.y as f32 / 256.0,
            glyph.width as f32 / 256.0, glyph.height as f32 / 256.0,
        ]).collect::<Vec<_>>()
    }).unwrap_or_else(|| vec![[0.0; 4]; 37]);
    anyhow::ensure!(tabular_uvs.len() == 37, "page-3 tabular UV table must be dense 37 entries");
    let tabular_uv_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("noir-dynamic-font-cell-page3-uv-table"), contents: bytemuck::cast_slice(&tabular_uvs),
        usage: wgpu::BufferUsages::STORAGE,
    });
    let fallback_tabular_texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("noir-dynamic-font-cell-page3-transparent-fallback"), size: wgpu::Extent3d { width: 1, height: 1, depth_or_array_layers: 1 },
        mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2, format: wgpu::TextureFormat::R8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST, view_formats: &[],
    });
    queue.write_texture(wgpu::TexelCopyTextureInfo { texture: &fallback_tabular_texture, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
                        &[0], wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(1), rows_per_image: Some(1) },
                        wgpu::Extent3d { width: 1, height: 1, depth_or_array_layers: 1 });
    let fallback_tabular_view = fallback_tabular_texture.create_view(&Default::default());
    let tabular_view = dynamic_atlas.map(|atlas| &atlas.view).unwrap_or(&fallback_tabular_view);
    let tabular_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
        label: Some("noir-dynamic-font-cell-page3-linear-sampler"), mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default()
    });

    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("noir-glyph-placement-bgl"),
        entries: &[
            wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::VERTEX, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 1, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Texture { multisampled: false, view_dimension: wgpu::TextureViewDimension::D2Array, sample_type: wgpu::TextureSampleType::Float { filterable: true } }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering), count: None },
            wgpu::BindGroupLayoutEntry { binding: 3, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Texture { multisampled: false, view_dimension: wgpu::TextureViewDimension::D2, sample_type: wgpu::TextureSampleType::Float { filterable: true } }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 4, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering), count: None },
            wgpu::BindGroupLayoutEntry { binding: 5, visibility: wgpu::ShaderStages::VERTEX, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 6, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Texture { multisampled: false, view_dimension: wgpu::TextureViewDimension::D2, sample_type: wgpu::TextureSampleType::Float { filterable: true } }, count: None },
            wgpu::BindGroupLayoutEntry { binding: 7, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering), count: None },
        ],
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("noir-glyph-placement-bind-group"), layout: &bgl,
        entries: &[
            wgpu::BindGroupEntry { binding: 0, resource: glyph_buffer.as_entire_binding() },
            wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&legacy_view) },
            wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::Sampler(&legacy_sampler) },
            wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::TextureView(font_view) },
            wgpu::BindGroupEntry { binding: 4, resource: wgpu::BindingResource::Sampler(&font_sampler) },
            wgpu::BindGroupEntry { binding: 5, resource: tabular_uv_buffer.as_entire_binding() },
            wgpu::BindGroupEntry { binding: 6, resource: wgpu::BindingResource::TextureView(tabular_view) },
            wgpu::BindGroupEntry { binding: 7, resource: wgpu::BindingResource::Sampler(&tabular_sampler) },
        ],
    });
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("noir-glyph-placement-shader"), source: wgpu::ShaderSource::Wgsl(include_str!("../host_placement.wgsl").into())
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("noir-glyph-placement-layout"), bind_group_layouts: &[Some(&bgl)], immediate_size: 0
    });
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("noir-glyph-placement-pipeline"), layout: Some(&layout),
        vertex: wgpu::VertexState { module: &shader, entry_point: Some("vs_main"), buffers: &[Some(unit_layout()), Some(glyph_placement_layout())], compilation_options: Default::default() },
        fragment: Some(wgpu::FragmentState { module: &shader, entry_point: Some("fs_main"), targets: &[Some(wgpu::ColorTargetState { format, blend: Some(wgpu::BlendState::ALPHA_BLENDING), write_mask: wgpu::ColorWrites::ALL })], compilation_options: Default::default() }),
        primitive: wgpu::PrimitiveState::default(), depth_stencil: None, multisample: wgpu::MultisampleState::default(), multiview_mask: None, cache: None,
    });
    Ok((bind_group, pipeline))
}
fn unit_layout<'a>()->wgpu::VertexBufferLayout<'a>{wgpu::VertexBufferLayout{array_stride:8,step_mode:wgpu::VertexStepMode::Vertex,attributes:&[wgpu::VertexAttribute{format:wgpu::VertexFormat::Float32x2,offset:0,shader_location:0}]}}
fn static_instance_layout<'a>()->wgpu::VertexBufferLayout<'a>{wgpu::VertexBufferLayout{array_stride:44,step_mode:wgpu::VertexStepMode::Instance,attributes:&[wgpu::VertexAttribute{format:wgpu::VertexFormat::Float32x2,offset:0,shader_location:1},wgpu::VertexAttribute{format:wgpu::VertexFormat::Float32x2,offset:8,shader_location:2},wgpu::VertexAttribute{format:wgpu::VertexFormat::Float32x4,offset:16,shader_location:3},wgpu::VertexAttribute{format:wgpu::VertexFormat::Uint32,offset:32,shader_location:4},wgpu::VertexAttribute{format:wgpu::VertexFormat::Uint32,offset:36,shader_location:5},wgpu::VertexAttribute{format:wgpu::VertexFormat::Uint32,offset:40,shader_location:6}]}}

// Compiler -> GPU 的固定 48-byte placement ABI。slot 0/1/2 直接携带 NDC quad 和 UV；
// shader 只在 `dynamic != 0` 时读取 glyph storage 的一个 u32 以取得变化后的 atlas cell。
fn glyph_placement_layout<'a>()->wgpu::VertexBufferLayout<'a>{wgpu::VertexBufferLayout{array_stride:GLYPH_PLACEMENT_BYTES as u64,step_mode:wgpu::VertexStepMode::Instance,attributes:&[
    wgpu::VertexAttribute{format:wgpu::VertexFormat::Float32x2,offset:0,shader_location:1},
    wgpu::VertexAttribute{format:wgpu::VertexFormat::Float32x2,offset:8,shader_location:2},
    wgpu::VertexAttribute{format:wgpu::VertexFormat::Float32x4,offset:16,shader_location:3},
    wgpu::VertexAttribute{format:wgpu::VertexFormat::Uint32,offset:32,shader_location:4},
    wgpu::VertexAttribute{format:wgpu::VertexFormat::Uint32,offset:36,shader_location:5},
    wgpu::VertexAttribute{format:wgpu::VertexFormat::Uint32,offset:40,shader_location:6},
    wgpu::VertexAttribute{format:wgpu::VertexFormat::Float32,offset:44,shader_location:7},
]}}

fn rects_intersect(left: [f32;4], right: [f32;4]) -> bool {
    left[0] < right[0] + right[2] && right[0] < left[0] + left[2]
        && left[1] < right[1] + right[3] && right[1] < left[1] + left[3]
}

// 受限 Noir profile 的 tile 表最多 64 项。compiler 提供升序且无重复的 tile_ids；host
// 只验证并压缩成一个固定 word，事件期的合并是 OR，而非 HashSet 或 rect 运算。
fn tile_mask(tile_ids: &[usize], tile_count: usize, owner: &str) -> Result<u64> {
    anyhow::ensure!(tile_count <= 64, "{owner}: compiler tile count {tile_count} exceeds fixed u64 selection mask");
    anyhow::ensure!(!tile_ids.is_empty(), "{owner}: compiler emitted an empty tile_ids plan");
    let mut mask = 0u64;
    let mut previous = None;
    for &tile_id in tile_ids {
        anyhow::ensure!(tile_id < tile_count, "{owner}: tile ID {tile_id} exceeds compiled tile table");
        if let Some(prior) = previous {
            anyhow::ensure!(prior < tile_id, "{owner}: tile IDs must be strictly ascending and unique");
        }
        mask |= 1u64 << tile_id;
        previous = Some(tile_id);
    }
    Ok(mask)
}

fn sha256_hex(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn safe_font_asset_path(scene_dir: &Path, declared: &str) -> Result<PathBuf> {
    let relative = Path::new(declared);
    anyhow::ensure!(!relative.is_absolute() && relative.components().all(|component| matches!(component, std::path::Component::Normal(_))),
                    "font asset path must be a safe relative path: {declared}");
    let direct = scene_dir.join(relative);
    let project_root = scene_dir.parent().unwrap_or(scene_dir);
    let fallback = project_root.join(relative);
    let candidate = if direct.is_file() { direct } else { fallback };
    anyhow::ensure!(candidate.is_file(), "font asset path does not exist relative to Scene: {declared}");
    Ok(candidate)
}

fn compiler_font_assets(scene: &Scene, scene_dir: &Path) -> Result<Vec<VerifiedFontAsset>> {
    let mut face_ids = HashSet::new();
    let mut atlas_pages = HashSet::new();
    let mut verified = Vec::with_capacity(scene.font_assets.len());
    for plan in &scene.font_assets {
        anyhow::ensure!(plan.abi_schema == FONT_ASSET_PLAN_ABI_SCHEMA && plan.abi_revision == FONT_ASSET_PLAN_ABI_REVISION,
                        "font asset {} has unsupported ABI {}@{}", plan.face_id, plan.abi_schema, plan.abi_revision);
        anyhow::ensure!(!plan.face_id.is_empty() && face_ids.insert(plan.face_id.as_str()),
                        "font asset face_id must be non-empty and unique: {}", plan.face_id);
        anyhow::ensure!(plan.renderer_kind == "atlas-gray" && plan.activation == "registered-inactive",
                        "font asset {} uses unsupported renderer/activation {}/{}", plan.face_id, plan.renderer_kind, plan.activation);
        anyhow::ensure!(plan.atlas_page == 2 && atlas_pages.insert(plan.atlas_page),
                        "font asset {} must own isolated atlas page 2", plan.face_id);
        anyhow::ensure!(plan.atlas_channels == 1 && plan.atlas_width > 0 && plan.atlas_height > 0
                        && plan.pixel_size > 0 && plan.line_height > 0 && plan.glyph_domain_first == 0 && plan.glyph_domain_count > 0,
                        "font asset {} has invalid R8 geometry or glyph domain", plan.face_id);
        anyhow::ensure!(plan.font_sha256.len() == 64 && plan.atlas_sha256.len() == 64
                        && plan.font_sha256.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
                        && plan.atlas_sha256.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase()),
                        "font asset {} hashes must be lowercase SHA-256", plan.face_id);
        let manifest_path = safe_font_asset_path(scene_dir, &plan.manifest_path)?;
        let atlas_path = safe_font_asset_path(scene_dir, &plan.atlas_path)?;
        let manifest_bytes = fs::read(&manifest_path).with_context(|| format!("read font manifest {}", manifest_path.display()))?;
        let manifest: FontManifest = serde_json::from_slice(&manifest_bytes)
            .with_context(|| format!("parse font manifest {}", manifest_path.display()))?;
        anyhow::ensure!(manifest.schema == "noir-font-asset-manifest-v1" && manifest.revision == 1,
                        "font asset {} manifest ABI mismatch", plan.face_id);
        anyhow::ensure!(manifest.face_id == plan.face_id && manifest.renderer_kind == plan.renderer_kind
                        && manifest.font_sha256 == plan.font_sha256 && manifest.atlas_sha256 == plan.atlas_sha256,
                        "font asset {} Scene/manifest identity mismatch", plan.face_id);
        anyhow::ensure!(manifest.atlas.width == plan.atlas_width && manifest.atlas.height == plan.atlas_height
                        && manifest.atlas.channels == plan.atlas_channels && manifest.atlas.mode == "r8"
                        && manifest.metrics.pixel_size == plan.pixel_size && manifest.metrics.line_height == plan.line_height,
                        "font asset {} Scene/manifest geometry mismatch", plan.face_id);
        anyhow::ensure!(manifest.glyph_count == plan.glyph_domain_count
                        && manifest.glyphs.len() == plan.glyph_domain_count as usize
                        && manifest.glyphs.iter().enumerate().all(|(index, glyph)| glyph.glyph_id == index as u32),
                        "font asset {} manifest glyph domain is not dense 0..count-1", plan.face_id);
        anyhow::ensure!(manifest.glyphs.iter().all(|glyph| glyph.width > 0 && glyph.height > 0
                        && glyph.x.checked_add(glyph.width).is_some_and(|right| right <= plan.atlas_width)
                        && glyph.y.checked_add(glyph.height).is_some_and(|bottom| bottom <= plan.atlas_height)
                        && glyph.advance.is_finite() && glyph.advance > 0.0),
                        "font asset {} manifest glyph metrics escape atlas or have non-positive advance", plan.face_id);
        let atlas_bytes = fs::read(&atlas_path).with_context(|| format!("read font atlas {}", atlas_path.display()))?;
        anyhow::ensure!(atlas_bytes.len() == (plan.atlas_width as usize) * (plan.atlas_height as usize),
                        "font asset {} R8 length does not match Scene geometry", plan.face_id);
        anyhow::ensure!(sha256_hex(&atlas_bytes) == plan.atlas_sha256,
                        "font asset {} atlas SHA-256 mismatch", plan.face_id);
        println!("compiler font asset: face={} page={} glyphs={} atlas={}x{} r8 activation={} manifest={} atlas={}",
                 plan.face_id, plan.atlas_page, plan.glyph_domain_count, plan.atlas_width, plan.atlas_height,
                 plan.activation, manifest_path.display(), atlas_path.display());
        verified.push(VerifiedFontAsset { plan: plan.clone(), atlas_bytes, manifest_path, atlas_path, glyphs: manifest.glyphs });
    }
    Ok(verified)
}

fn compiler_dynamic_font_cells(scene: &Scene, scene_dir: &Path) -> Result<Option<VerifiedDynamicFontCellAsset>> {
    let Some(plan) = &scene.dynamic_font_cell_plan else { return Ok(None); };
    anyhow::ensure!(plan.abi_schema == DYNAMIC_FONT_CELL_PLAN_ABI_SCHEMA && plan.abi_revision == DYNAMIC_FONT_CELL_PLAN_ABI_REVISION,
                    "unsupported dynamic_font_cell_plan payload {}@{}", plan.abi_schema, plan.abi_revision);
    anyhow::ensure!(plan.face_id == "noir-table-body-mono-16" && plan.atlas_page == 3
                    && plan.coverage_policy == "tabular-body-v1" && plan.advance_policy == "fixed-tabular"
                    && plan.fixed_advance == 10.0 && plan.glyph_domain_first == 0 && plan.glyph_domain_count == 37,
                    "dynamic_font_cell_plan uses unsupported face/page/coverage/advance policy");
    anyhow::ensure!(plan.atlas_width == 256 && plan.atlas_height == 256 && plan.atlas_channels == 1
                    && plan.font_sha256.len() == 64 && plan.atlas_sha256.len() == 64,
                    "dynamic_font_cell_plan has invalid fixed R8 geometry or hash length");
    let manifest_path = safe_font_asset_path(scene_dir, &plan.manifest_path)?;
    let atlas_path = safe_font_asset_path(scene_dir, &plan.atlas_path)?;
    let manifest_bytes = fs::read(&manifest_path).with_context(|| format!("read dynamic font manifest {}", manifest_path.display()))?;
    let manifest: FontManifest = serde_json::from_slice(&manifest_bytes)
        .with_context(|| format!("parse dynamic font manifest {}", manifest_path.display()))?;
    anyhow::ensure!(manifest.schema == "noir-font-asset-manifest-v1" && manifest.revision == 1
                    && manifest.face_id == plan.face_id && manifest.renderer_kind == "atlas-gray"
                    && manifest.font_sha256 == plan.font_sha256 && manifest.atlas_sha256 == plan.atlas_sha256
                    && manifest.coverage_policy == plan.coverage_policy && manifest.advance_policy == plan.advance_policy
                    && manifest.fixed_advance == plan.fixed_advance,
                    "dynamic_font_cell_plan Scene/manifest identity or policy mismatch");
    anyhow::ensure!(manifest.atlas.width == plan.atlas_width && manifest.atlas.height == plan.atlas_height
                    && manifest.atlas.channels == 1 && manifest.atlas.mode == "r8"
                    && manifest.glyph_count == 37 && manifest.glyphs.len() == 37
                    && manifest.glyphs.iter().enumerate().all(|(index, glyph)| glyph.glyph_id == index as u32)
                    && manifest.glyphs.iter().all(|glyph| glyph.advance == 10.0 && glyph.width > 0 && glyph.height > 0
                        && glyph.x.checked_add(glyph.width).is_some_and(|right| right <= 256)
                        && glyph.y.checked_add(glyph.height).is_some_and(|bottom| bottom <= 256)),
                    "dynamic_font_cell_plan manifest does not prove dense fixed-tabular glyph metrics");
    let expected = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    anyhow::ensure!(manifest.glyphs.iter().map(|glyph| glyph.character.as_str()).collect::<String>() == expected
                    && manifest.glyphs.iter().map(|glyph| glyph.codepoint).collect::<Vec<_>>()
                       == expected.chars().map(|ch| ch as u32).collect::<Vec<_>>(),
                    "dynamic_font_cell_plan manifest glyph character domain is not TABULAR_BODY_V1");
    let atlas_bytes = fs::read(&atlas_path).with_context(|| format!("read dynamic font atlas {}", atlas_path.display()))?;
    anyhow::ensure!(atlas_bytes.len() == 256 * 256 && sha256_hex(&atlas_bytes) == plan.atlas_sha256,
                    "dynamic_font_cell_plan R8 atlas length or SHA-256 mismatch");
    let mut admitted_tables = HashSet::new();
    for table in &plan.tables {
        anyhow::ensure!(admitted_tables.insert(table.table_id.as_str()) && table.register_width > 0 && table.physical_slots > 0
                        && table.placement_slots.len() == table.register_width * table.physical_slots
                        && table.glyph_word_offsets.len() == table.placement_slots.len()
                        && table.cell_uv.len() == table.placement_slots.len() && table.cell_advance.len() == table.placement_slots.len()
                        && table.packet_worklist_index == 2 && !table.tile_ids.is_empty(),
                        "dynamic font cell table {} violates fixed cell cardinality/authority", table.table_id);
        let list = scene.virtual_list_plans.iter().find(|list| list.id == table.list_id)
            .with_context(|| format!("dynamic font cell table {} references unknown list {}", table.table_id, table.list_id))?;
        let register = list.data_register_table.as_ref()
            .with_context(|| format!("dynamic font cell table {} list lacks data-register-table", table.table_id))?;
        anyhow::ensure!(register.id == table.table_id && register.register_width == table.register_width
                        && list.physical_slots == table.physical_slots && register.atlas_page == 3
                        && register.font_face.as_deref() == Some(plan.face_id.as_str()),
                        "dynamic font cell table {} disagrees with virtual-list page-3 register declaration", table.table_id);
        anyhow::ensure!(table.tile_ids == list.visible_row_tile_ids,
                        "dynamic font cell table {} tile authority disagrees with frozen virtual-list", table.table_id);
        for index in 0..table.placement_slots.len() {
            let slot = table.placement_slots[index];
            let placement = scene.glyph_placement_plan.get(slot)
                .with_context(|| format!("dynamic font cell table {} placement slot {} out of range", table.table_id, slot))?;
            anyhow::ensure!(placement.atlas_page == 3 && placement.dynamic && placement.face_id.as_deref() == Some(plan.face_id.as_str())
                            && placement.glyph_word_offset == table.glyph_word_offsets[index]
                            && placement.glyph_id >> 16 == 3 && (placement.glyph_id & 0xffff) < 37
                            && (placement.advance - 10.0).abs() <= 1e-6
                            && placement.atlas_uv.iter().zip(table.cell_uv[index].iter()).all(|(left, right)| (*left - *right).abs() <= 1e-6)
                            && (table.cell_advance[index] - 10.0).abs() <= 1e-6,
                            "dynamic font cell table {} placement {} escapes page-3 fixed-cell proof", table.table_id, slot);
        }
    }
    anyhow::ensure!(!plan.tables.is_empty(), "dynamic_font_cell_plan has no admitted table authority");
    println!("compiler dynamic font cells: face={} page=3 glyphs=37 tables={} fixed_advance=10 atlas={}x{} manifest={} atlas={}",
             plan.face_id, plan.tables.len(), plan.atlas_width, plan.atlas_height, manifest_path.display(), atlas_path.display());
    Ok(Some(VerifiedDynamicFontCellAsset { atlas_bytes, manifest_path, atlas_path, glyphs: manifest.glyphs }))
}

fn make_dynamic_font_cell_atlas(device: &wgpu::Device, queue: &wgpu::Queue, asset: Option<&VerifiedDynamicFontCellAsset>) -> Result<Option<RegisteredDynamicFontAtlas>> {
    let Some(asset) = asset else { return Ok(None); };
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("noir-dynamic-font-cell-page3-r8"), size: wgpu::Extent3d { width: 256, height: 256, depth_or_array_layers: 1 },
        mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2, format: wgpu::TextureFormat::R8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST, view_formats: &[],
    });
    queue.write_texture(wgpu::TexelCopyTextureInfo { texture: &texture, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
                        &asset.atlas_bytes, wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(256), rows_per_image: Some(256) },
                        wgpu::Extent3d { width: 256, height: 256, depth_or_array_layers: 1 });
    println!("dynamic-font-cell-atlas-upload: page=3 bytes={} glyphs={} manifest={} atlas={}", asset.atlas_bytes.len(), asset.glyphs.len(), asset.manifest_path.display(), asset.atlas_path.display());
    Ok(Some(RegisteredDynamicFontAtlas { view: texture.create_view(&Default::default()), _texture: texture }))
}

fn compiler_font_placements(scene: &Scene, assets: &[VerifiedFontAsset]) -> Result<()> {
    let assets_by_face = assets.iter().map(|asset| (asset.plan.face_id.as_str(), asset)).collect::<HashMap<_, _>>();
    let mut active = 0usize;
    for placement in &scene.glyph_placement_plan {
        anyhow::ensure!(placement.ndc_size[0].is_finite() && placement.ndc_size[1].is_finite()
                        && placement.ndc_size[0] > 0.0 && placement.ndc_size[1] > 0.0,
                        "glyph placement {} has non-positive or non-finite NDC geometry", placement.node);
        match placement.atlas_page {
            0 | 1 => anyhow::ensure!(placement.face_id.is_none(),
                                      "legacy glyph placement {} page {} must not carry face_id", placement.node, placement.atlas_page),
            2 => {
                let face_id = placement.face_id.as_deref()
                    .context("page-2 glyph placement lacks required face_id")?;
                let asset = assets_by_face.get(face_id)
                    .with_context(|| format!("page-2 glyph placement {} references unregistered face {}", placement.node, face_id))?;
                anyhow::ensure!(!placement.dynamic, "page-2 glyph placement {} must be static in font_placement_plan v1", placement.node);
                anyhow::ensure!(asset.plan.atlas_page == 2 && placement.glyph_id >> 16 == 2,
                                "page-2 glyph placement {} has page-inconsistent asset or glyph ID", placement.node);
                let glyph_index = placement.glyph_id & 0xffff;
                anyhow::ensure!(glyph_index >= asset.plan.glyph_domain_first
                                && glyph_index < asset.plan.glyph_domain_first + asset.plan.glyph_domain_count,
                                "page-2 glyph placement {} glyph {} is outside face {} domain", placement.node, glyph_index, face_id);
                let glyph = asset.glyphs.get(glyph_index as usize)
                    .with_context(|| format!("page-2 glyph placement {} lacks manifest glyph {}", placement.node, glyph_index))?;
                anyhow::ensure!(glyph.glyph_id == glyph_index,
                                "page-2 glyph placement {} manifest glyph domain is unstable", placement.node);
                let expected_uv = [
                    glyph.x as f32 / asset.plan.atlas_width as f32,
                    glyph.y as f32 / asset.plan.atlas_height as f32,
                    glyph.width as f32 / asset.plan.atlas_width as f32,
                    glyph.height as f32 / asset.plan.atlas_height as f32,
                ];
                anyhow::ensure!(placement.atlas_uv.iter().zip(expected_uv).all(|(actual, expected)| (*actual - expected).abs() <= 1e-6),
                                "page-2 glyph placement {} UV does not match face {} manifest glyph {}", placement.node, face_id, glyph_index);
                anyhow::ensure!((placement.advance - glyph.advance).abs() <= 1e-5,
                                "page-2 glyph placement {} advance does not match face {} manifest glyph {}", placement.node, face_id, glyph_index);
                active += 1;
            }
            3 => {
                let plan = scene.dynamic_font_cell_plan.as_ref()
                    .context("page-3 glyph placement exists without dynamic_font_cell_plan")?;
                anyhow::ensure!(placement.dynamic && placement.face_id.as_deref() == Some(plan.face_id.as_str())
                                && placement.glyph_id >> 16 == 3 && (placement.glyph_id & 0xffff) < 37
                                && (placement.advance - 10.0).abs() <= 1e-6,
                                "page-3 glyph placement {} violates dynamic fixed-cell pre-proof", placement.node);
            }
            page => anyhow::bail!("glyph placement {} uses unsupported atlas page {}", placement.node, page),
        }
    }
    println!("compiler font placement proof: active-page2-glyphs={} registered-font-assets={} mode=static-proportional-v1", active, assets.len());
    Ok(())
}

fn make_registered_font_atlases(device: &wgpu::Device, queue: &wgpu::Queue, assets: &[VerifiedFontAsset]) -> Result<Vec<RegisteredFontAtlas>> {
    let mut registered = Vec::with_capacity(assets.len());
    for asset in assets {
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("noir-fontc-r8-atlas-registered-inactive"),
            size: wgpu::Extent3d { width: asset.plan.atlas_width, height: asset.plan.atlas_height, depth_or_array_layers: 1 },
            mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        queue.write_texture(
            wgpu::TexelCopyTextureInfo { texture: &texture, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
            &asset.atlas_bytes,
            wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(asset.plan.atlas_width), rows_per_image: Some(asset.plan.atlas_height) },
            wgpu::Extent3d { width: asset.plan.atlas_width, height: asset.plan.atlas_height, depth_or_array_layers: 1 },
        );
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        println!("font-atlas-upload: face={} page={} bytes={} sha256={} renderer=registered-inactive manifest={} atlas={}",
                 asset.plan.face_id, asset.plan.atlas_page, asset.atlas_bytes.len(), asset.plan.atlas_sha256,
                 asset.manifest_path.display(), asset.atlas_path.display());
        registered.push(RegisteredFontAtlas {
            face_id: asset.plan.face_id.clone(), atlas_page: asset.plan.atlas_page,
            width: asset.plan.atlas_width, height: asset.plan.atlas_height,
            atlas_sha256: asset.plan.atlas_sha256.clone(), glyphs: asset.glyphs.clone(), view, _texture: texture,
        });
    }
    Ok(registered)
}

fn compiler_abi_contracts(scene: &Scene) -> Result<()> {
    anyhow::ensure!(scene.abi_contracts.virtual_list_plan.schema == VIRTUAL_LIST_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.virtual_list_plan.revision == VIRTUAL_LIST_PLAN_ABI_REVISION,
                    "unsupported virtual_list_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.virtual_list_plan.schema, scene.abi_contracts.virtual_list_plan.revision,
                    VIRTUAL_LIST_PLAN_ABI_SCHEMA, VIRTUAL_LIST_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.row_activation_plan.schema == ROW_ACTIVATION_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.row_activation_plan.revision == ROW_ACTIVATION_PLAN_ABI_REVISION,
                    "unsupported row_activation_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.row_activation_plan.schema, scene.abi_contracts.row_activation_plan.revision,
                    ROW_ACTIVATION_PLAN_ABI_SCHEMA, ROW_ACTIVATION_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.scrollbar_plan.schema == SCROLLBAR_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.scrollbar_plan.revision == SCROLLBAR_PLAN_ABI_REVISION,
                    "unsupported scrollbar_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.scrollbar_plan.schema, scene.abi_contracts.scrollbar_plan.revision,
                    SCROLLBAR_PLAN_ABI_SCHEMA, SCROLLBAR_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.list_navigation_plan.schema == LIST_NAVIGATION_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.list_navigation_plan.revision == LIST_NAVIGATION_PLAN_ABI_REVISION,
                    "unsupported list_navigation_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.list_navigation_plan.schema, scene.abi_contracts.list_navigation_plan.revision,
                    LIST_NAVIGATION_PLAN_ABI_SCHEMA, LIST_NAVIGATION_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.log_browser_plan.schema == LOG_BROWSER_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.log_browser_plan.revision == LOG_BROWSER_PLAN_ABI_REVISION,
                    "unsupported log_browser_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.log_browser_plan.schema, scene.abi_contracts.log_browser_plan.revision,
                    LOG_BROWSER_PLAN_ABI_SCHEMA, LOG_BROWSER_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.font_asset_plan.schema == FONT_ASSET_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.font_asset_plan.revision == FONT_ASSET_PLAN_ABI_REVISION,
                    "unsupported font_asset_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.font_asset_plan.schema, scene.abi_contracts.font_asset_plan.revision,
                    FONT_ASSET_PLAN_ABI_SCHEMA, FONT_ASSET_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.font_placement_plan.schema == FONT_PLACEMENT_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.font_placement_plan.revision == FONT_PLACEMENT_PLAN_ABI_REVISION,
                    "unsupported font_placement_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.font_placement_plan.schema, scene.abi_contracts.font_placement_plan.revision,
                    FONT_PLACEMENT_PLAN_ABI_SCHEMA, FONT_PLACEMENT_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.dynamic_font_cell_plan.schema == DYNAMIC_FONT_CELL_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.dynamic_font_cell_plan.revision == DYNAMIC_FONT_CELL_PLAN_ABI_REVISION,
                    "unsupported dynamic_font_cell_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.dynamic_font_cell_plan.schema, scene.abi_contracts.dynamic_font_cell_plan.revision,
                    DYNAMIC_FONT_CELL_PLAN_ABI_SCHEMA, DYNAMIC_FONT_CELL_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.visual_language_plan.schema == VISUAL_LANGUAGE_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.visual_language_plan.revision == VISUAL_LANGUAGE_PLAN_ABI_REVISION,
                    "unsupported visual_language_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.visual_language_plan.schema, scene.abi_contracts.visual_language_plan.revision,
                    VISUAL_LANGUAGE_PLAN_ABI_SCHEMA, VISUAL_LANGUAGE_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.rounded_surface_plan.schema == ROUNDED_SURFACE_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.rounded_surface_plan.revision == ROUNDED_SURFACE_PLAN_ABI_REVISION,
                    "unsupported rounded_surface_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.rounded_surface_plan.schema, scene.abi_contracts.rounded_surface_plan.revision,
                    ROUNDED_SURFACE_PLAN_ABI_SCHEMA, ROUNDED_SURFACE_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.shadow_surface_plan.schema == SHADOW_SURFACE_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.shadow_surface_plan.revision == SHADOW_SURFACE_PLAN_ABI_REVISION,
                    "unsupported shadow_surface_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.shadow_surface_plan.schema, scene.abi_contracts.shadow_surface_plan.revision,
                    SHADOW_SURFACE_PLAN_ABI_SCHEMA, SHADOW_SURFACE_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.navigation_selection_plan.schema == NAVIGATION_SELECTION_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.navigation_selection_plan.revision == NAVIGATION_SELECTION_PLAN_ABI_REVISION,
                    "unsupported navigation_selection_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.navigation_selection_plan.schema, scene.abi_contracts.navigation_selection_plan.revision,
                    NAVIGATION_SELECTION_PLAN_ABI_SCHEMA, NAVIGATION_SELECTION_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.modal_focus_subgraph.schema == MODAL_FOCUS_SUBGRAPH_ABI_SCHEMA
                    && scene.abi_contracts.modal_focus_subgraph.revision == MODAL_FOCUS_SUBGRAPH_ABI_REVISION,
                    "unsupported modal_focus_subgraph ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.modal_focus_subgraph.schema, scene.abi_contracts.modal_focus_subgraph.revision,
                    MODAL_FOCUS_SUBGRAPH_ABI_SCHEMA, MODAL_FOCUS_SUBGRAPH_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.modal_focus_visual_plan.schema == MODAL_FOCUS_VISUAL_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.modal_focus_visual_plan.revision == MODAL_FOCUS_VISUAL_PLAN_ABI_REVISION,
                    "unsupported modal_focus_visual_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.modal_focus_visual_plan.schema, scene.abi_contracts.modal_focus_visual_plan.revision,
                    MODAL_FOCUS_VISUAL_PLAN_ABI_SCHEMA, MODAL_FOCUS_VISUAL_PLAN_ABI_REVISION);
    anyhow::ensure!(scene.abi_contracts.material_observability_workbench_plan.schema == MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_SCHEMA
                    && scene.abi_contracts.material_observability_workbench_plan.revision == MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_REVISION,
                    "unsupported material_observability_workbench_plan ABI {}@{}; expected {}@{}",
                    scene.abi_contracts.material_observability_workbench_plan.schema, scene.abi_contracts.material_observability_workbench_plan.revision,
                    MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_SCHEMA, MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_REVISION);
    println!("compiler ABI contracts: virtual-list={}@{} row-activation={}@{} scrollbar={}@{} list-navigation={}@{} log-browser={}@{} font-asset={}@{} font-placement={}@{} dynamic-font-cell={}@{} visual-language={}@{} rounded-surface={}@{} shadow-surface={}@{} navigation-selection={}@{} modal-focus={}@{} modal-focus-visual={}@{} workbench={}@{} frozen",
             scene.abi_contracts.virtual_list_plan.schema, scene.abi_contracts.virtual_list_plan.revision,
             scene.abi_contracts.row_activation_plan.schema, scene.abi_contracts.row_activation_plan.revision,
             scene.abi_contracts.scrollbar_plan.schema, scene.abi_contracts.scrollbar_plan.revision,
             scene.abi_contracts.list_navigation_plan.schema, scene.abi_contracts.list_navigation_plan.revision,
             scene.abi_contracts.log_browser_plan.schema, scene.abi_contracts.log_browser_plan.revision,
             scene.abi_contracts.font_asset_plan.schema, scene.abi_contracts.font_asset_plan.revision,
             scene.abi_contracts.font_placement_plan.schema, scene.abi_contracts.font_placement_plan.revision,
             scene.abi_contracts.dynamic_font_cell_plan.schema, scene.abi_contracts.dynamic_font_cell_plan.revision,
             scene.abi_contracts.visual_language_plan.schema, scene.abi_contracts.visual_language_plan.revision,
             scene.abi_contracts.rounded_surface_plan.schema, scene.abi_contracts.rounded_surface_plan.revision,
             scene.abi_contracts.shadow_surface_plan.schema, scene.abi_contracts.shadow_surface_plan.revision,
             scene.abi_contracts.navigation_selection_plan.schema, scene.abi_contracts.navigation_selection_plan.revision,
             scene.abi_contracts.modal_focus_subgraph.schema, scene.abi_contracts.modal_focus_subgraph.revision,
             scene.abi_contracts.modal_focus_visual_plan.schema, scene.abi_contracts.modal_focus_visual_plan.revision,
             scene.abi_contracts.material_observability_workbench_plan.schema, scene.abi_contracts.material_observability_workbench_plan.revision);
    Ok(())
}

#[derive(Clone, Copy)]
struct VerifiedVisualCanvas { width: u32, height: u32, margin: f32 }

fn compiler_visual_language_plan(scene: &Scene) -> Result<VerifiedVisualCanvas> {
    let plan = &scene.visual_language_plan;
    anyhow::ensure!(plan.abi_schema == VISUAL_LANGUAGE_PLAN_ABI_SCHEMA && plan.abi_revision == VISUAL_LANGUAGE_PLAN_ABI_REVISION,
                    "unsupported visual_language_plan payload {}@{}", plan.abi_schema, plan.abi_revision);
    anyhow::ensure!(plan.canvas.width.is_finite() && plan.canvas.height.is_finite() && plan.canvas.margin.is_finite()
                    && plan.canvas.width > 0.0 && plan.canvas.height > 0.0 && plan.canvas.margin >= 0.0,
                    "visual_language_plan has non-finite or non-positive canvas geometry");
    let (expected_width, expected_height, expected_margin) = match plan.preset.as_str() {
        "bench" => (640u32, 360u32, 16.0f32),
        "desktop-wide" => (1280u32, 720u32, 32.0f32),
        _ => anyhow::bail!("visual_language_plan uses unsupported preset {}", plan.preset),
    };
    anyhow::ensure!(plan.canvas.width == expected_width as f32 && plan.canvas.height == expected_height as f32 && plan.canvas.margin == expected_margin,
                    "visual_language_plan {} geometry must be {}x{} margin {}", plan.preset, expected_width, expected_height, expected_margin);
    for layout in &scene.layout_plan {
        let x = (layout.ndc_pos[0] + 1.0) * plan.canvas.width * 0.5;
        let y = (1.0 - layout.ndc_pos[1] - layout.ndc_size[1]) * plan.canvas.height * 0.5;
        let width = layout.ndc_size[0] * plan.canvas.width * 0.5;
        let height = layout.ndc_size[1] * plan.canvas.height * 0.5;
        anyhow::ensure!(x.is_finite() && y.is_finite() && width.is_finite() && height.is_finite()
                        && x >= -0.001 && y >= -0.001 && width >= 0.0 && height >= 0.0
                        && x + width <= plan.canvas.width + 0.001 && y + height <= plan.canvas.height + 0.001,
                        "layout {} escapes compiler-owned {} canvas", layout.id, plan.preset);
    }
    println!("compiler visual language: preset={} canvas={}x{} margin={} static-proof=layout-contained",
             plan.preset, expected_width, expected_height, expected_margin);
    Ok(VerifiedVisualCanvas { width: expected_width, height: expected_height, margin: expected_margin })
}

fn compiler_rounded_surface_plan(scene: &Scene) -> Result<Vec<GpuRoundedSurfaceMeta>> {
    let mut metadata = vec![GpuRoundedSurfaceMeta::zeroed(); scene.resource_budget.instance_capacity];
    let Some(plan) = &scene.rounded_surface_plan else {
        anyhow::ensure!(scene.visual_language_plan.preset == "bench",
                        "desktop-wide visual Scene may not disable rounded_surface_plan v1");
        println!("compiler rounded surfaces: disabled surfaces=0 metadata-slots={}", metadata.len());
        return Ok(metadata);
    };
    anyhow::ensure!(plan.abi_schema == ROUNDED_SURFACE_PLAN_ABI_SCHEMA
                    && plan.abi_revision == ROUNDED_SURFACE_PLAN_ABI_REVISION
                    && plan.aa_width_px.is_finite() && (plan.aa_width_px - 1.0).abs() <= 1e-6
                    && !plan.surfaces.is_empty() && plan.surfaces.len() <= scene.resource_budget.instance_capacity,
                    "rounded_surface_plan payload must be nonempty v1 with fixed 1px antialias width and bounded surface count");
    let mut layout_by_offset = HashMap::new();
    for layout in &scene.layout_plan {
        anyhow::ensure!(layout_by_offset.insert(layout._instance_offset, layout).is_none(),
                        "duplicate layout instance offset {} while proving rounded surfaces", layout._instance_offset);
    }
    let mut ids = HashSet::new();
    let mut slots = HashSet::new();
    for surface in &plan.surfaces {
        anyhow::ensure!(ids.insert(surface.id.as_str()) && slots.insert(surface.instance_offset)
                        && surface.instance_offset > 0 && surface.instance_offset % std::mem::size_of::<QuadInstance>() == 0,
                        "rounded surface {} has duplicate, root, or misaligned QuadInstance offset", surface.id);
        let slot = surface.instance_offset / std::mem::size_of::<QuadInstance>();
        anyhow::ensure!(slot < metadata.len(), "rounded surface {} slot {} exceeds instance capacity", surface.id, slot);
        let layout = layout_by_offset.get(&surface.instance_offset)
            .with_context(|| format!("rounded surface {} references unknown layout offset {}", surface.id, surface.instance_offset))?;
        anyhow::ensure!(layout.id == surface.id && matches!(layout.tag.as_str(), "stack" | "button"),
                        "rounded surface {} must target its own static stack/button layout", surface.id);
        let x = (layout.ndc_pos[0] + 1.0) * scene.visual_language_plan.canvas.width * 0.5;
        let y = (1.0 - layout.ndc_pos[1] - layout.ndc_size[1]) * scene.visual_language_plan.canvas.height * 0.5;
        let width = layout.ndc_size[0] * scene.visual_language_plan.canvas.width * 0.5;
        let height = layout.ndc_size[1] * scene.visual_language_plan.canvas.height * 0.5;
        anyhow::ensure!([surface.x, surface.y, surface.width, surface.height, surface.radius_px, surface.aa_width_px]
                            .iter().all(|value| value.is_finite())
                        && surface.width > 0.0 && surface.height > 0.0 && surface.radius_px > 0.0
                        && surface.radius_px <= surface.width.min(surface.height) * 0.5
                        && (surface.aa_width_px - plan.aa_width_px).abs() <= 1e-6
                        && (surface.x - x).abs() <= 1e-3 && (surface.y - y).abs() <= 1e-3
                        && (surface.width - width).abs() <= 1e-3 && (surface.height - height).abs() <= 1e-3,
                        "rounded surface {} geometry/radius/AA disagrees with compiler layout", surface.id);
        metadata[slot] = GpuRoundedSurfaceMeta { radius_px: surface.radius_px, aa_width_px: surface.aa_width_px, width_px: surface.width, height_px: surface.height };
    }
    println!("compiler rounded surfaces: v1 surfaces={} metadata-slots={} aa-width=1px immutable-instance-slots",
             plan.surfaces.len(), metadata.len());
    Ok(metadata)
}

fn shadow_layer_recipe(elevation: u32) -> &'static [(f32, f32)] {
    match elevation {
        1 => &[(3.0, 0.14), (7.0, 0.055)],
        2 => &[(4.0, 0.17), (10.0, 0.070)],
        3 => &[(6.0, 0.19), (14.0, 0.080)],
        4 => &[(8.0, 0.21), (18.0, 0.090)],
        5 => &[(10.0, 0.23), (22.0, 0.100)],
        _ => &[],
    }
}

fn compiler_shadow_surface_plan(scene: &Scene) -> Result<(Vec<QuadInstance>, Vec<GpuShadowSurfaceMeta>)> {
    let Some(plan) = &scene.shadow_surface_plan else {
        anyhow::ensure!(scene.visual_language_plan.preset == "bench",
                        "desktop-wide visual Scene may not disable shadow_surface_plan v1");
        println!("compiler shadow surfaces: disabled layers=0 immutable-instances=0");
        return Ok((Vec::new(), Vec::new()));
    };
    anyhow::ensure!(plan.abi_schema == SHADOW_SURFACE_PLAN_ABI_SCHEMA && plan.abi_revision == SHADOW_SURFACE_PLAN_ABI_REVISION
                    && !plan.layers.is_empty() && plan.layers.len() <= scene.resource_budget.instance_capacity.saturating_mul(2),
                    "shadow_surface_plan payload must be nonempty bounded v1");
    let canvas_width = scene.visual_language_plan.canvas.width;
    let canvas_height = scene.visual_language_plan.canvas.height;
    let mut layouts = HashMap::new();
    for layout in &scene.layout_plan {
        anyhow::ensure!(layouts.insert(layout.id.as_str(), layout).is_none(),
                        "duplicate layout id {} while proving shadow surfaces", layout.id);
    }
    let mut ids = HashSet::new();
    let mut source_layers = HashSet::new();
    let mut instances = Vec::with_capacity(plan.layers.len());
    let mut metadata = Vec::with_capacity(plan.layers.len());
    for entry in &plan.layers {
        anyhow::ensure!(ids.insert(entry.id.as_str()) && source_layers.insert((entry.source_id.as_str(), entry.layer)),
                        "shadow layer {} has duplicate ID or source/layer address", entry.id);
        let layout = layouts.get(entry.source_id.as_str())
            .with_context(|| format!("shadow layer {} references unknown source {}", entry.id, entry.source_id))?;
        anyhow::ensure!(layout.tag == "stack" && layout.elevation == entry.elevation && entry.elevation >= 1 && entry.elevation <= 5
                        && layout._instance_offset == entry.source_instance_offset,
                        "shadow layer {} source/elevation/instance offset disagrees with frozen layout", entry.id);
        let recipe = shadow_layer_recipe(entry.elevation);
        anyhow::ensure!(entry.layer >= 1 && (entry.layer as usize) <= recipe.len(),
                        "shadow layer {} uses invalid v1 layer {} for elevation {}", entry.id, entry.layer, entry.elevation);
        let (expected_blur, expected_opacity) = recipe[entry.layer as usize - 1];
        let source_x = (layout.ndc_pos[0] + 1.0) * canvas_width * 0.5;
        let source_y = (1.0 - layout.ndc_pos[1] - layout.ndc_size[1]) * canvas_height * 0.5;
        let source_width = layout.ndc_size[0] * canvas_width * 0.5;
        let source_height = layout.ndc_size[1] * canvas_height * 0.5;
        anyhow::ensure!([entry.x, entry.y, entry.width, entry.height, entry.radius_px, entry.blur_px, entry.opacity]
                            .iter().all(|value| value.is_finite())
                        && source_width > 0.0 && source_height > 0.0
                        && entry.radius_px > 0.0 && entry.radius_px <= source_width.min(source_height) * 0.5
                        && (entry.blur_px - expected_blur).abs() <= 1e-6
                        && (entry.opacity - expected_opacity).abs() <= 1e-6
                        && (entry.x - (source_x - entry.blur_px)).abs() <= 1e-3
                        && (entry.y - (source_y - entry.blur_px)).abs() <= 1e-3
                        && (entry.width - (source_width + 2.0 * entry.blur_px)).abs() <= 1e-3
                        && (entry.height - (source_height + 2.0 * entry.blur_px)).abs() <= 1e-3,
                        "shadow layer {} geometry/recipe disagrees with compiler layout", entry.id);
        let ndc_pos = [2.0 * entry.x / canvas_width - 1.0,
                       1.0 - 2.0 * (entry.y + entry.height) / canvas_height];
        let ndc_size = [2.0 * entry.width / canvas_width, 2.0 * entry.height / canvas_height];
        instances.push(QuadInstance { pos: ndc_pos, size: ndc_size, color: [0.0, 0.0, 0.0, entry.opacity], glyph_word_offset: 0, glyph_enabled: 0, glyph_count: 0 });
        metadata.push(GpuShadowSurfaceMeta { radius_px: entry.radius_px, blur_px: entry.blur_px, source_width_px: source_width, source_height_px: source_height });
    }
    for layout in scene.layout_plan.iter().filter(|layout| layout.elevation > 0) {
        anyhow::ensure!(layout.tag == "stack", "elevated layout {} must be a static stack", layout.id);
        let recipe = shadow_layer_recipe(layout.elevation);
        anyhow::ensure!(!recipe.is_empty(), "layout {} has unsupported elevation {}", layout.id, layout.elevation);
        for layer in 1..=recipe.len() as u32 {
            anyhow::ensure!(source_layers.contains(&(layout.id.as_str(), layer)),
                            "elevated layout {} is missing required shadow layer {}", layout.id, layer);
        }
    }
    println!("compiler shadow surfaces: v1 layers={} elevated-sources={} immutable-shadow-instances=1pass",
             instances.len(), scene.layout_plan.iter().filter(|layout| layout.elevation > 0).count());
    Ok((instances, metadata))
}

fn compiler_virtual_list_plans(scene: &Scene) -> Result<Vec<CompiledVirtualListPlan>> {
    let visual_canvas = compiler_visual_language_plan(scene)?;
    let canvas_width = visual_canvas.width as f32;
    let canvas_height = visual_canvas.height as f32;
    let mut layout_by_id = HashMap::new();
    for layout in &scene.layout_plan {
        anyhow::ensure!(layout_by_id.insert(layout.id.as_str(), layout).is_none(),
                        "duplicate layout id {} while proving virtual lists", layout.id);
    }
    let mut compiled = Vec::with_capacity(scene.virtual_list_plans.len());
    for plan in &scene.virtual_list_plans {
        anyhow::ensure!(plan.abi_schema == VIRTUAL_LIST_PLAN_ABI_SCHEMA && plan.abi_revision == VIRTUAL_LIST_PLAN_ABI_REVISION,
                        "virtual list {} has unsupported ABI {}@{}", plan.id, plan.abi_schema, plan.abi_revision);
        anyhow::ensure!(plan.capacity > 0, "virtual list {} has zero capacity", plan.id);
        let logical_capacity = if plan.logical_capacity == 0 { plan.capacity } else { plan.logical_capacity };
        let physical_slots = if plan.physical_slots == 0 { plan.capacity } else { plan.physical_slots };
        anyhow::ensure!(physical_slots == plan.capacity && physical_slots >= plan.visible_rows && logical_capacity >= physical_slots,
                        "virtual list {} has invalid logical/physical capacity proof", plan.id);
        let compiled_data_register_table = if let Some(table) = &plan.data_register_table {
            anyhow::ensure!(plan.recycling && table.capacity == logical_capacity && table.register_width > 0
                            && matches!(table.atlas_page, 1 | 3)
                            && (table.atlas_page == 1 || table.font_face.as_deref() == Some("noir-table-body-mono-16")),
                            "compact data-register-table for {} has invalid capacity/atlas/face proof", plan.id);
            anyhow::ensure!(plan.logical_data_ids.is_empty() && plan.logical_labels.is_empty() && plan.scroll_transitions.is_empty(),
                            "compact data-register-table {} must not serialize logical labels or per-viewport transitions", table.id);
            let seed_glyphs = compact_register_glyphs(&table.seed, table.register_width, table.atlas_page)
                .with_context(|| format!("compact data-register-table {} has invalid legacy glyph seed", table.id))?;
            let mut glyph_ids = Vec::with_capacity(table.capacity * table.register_width);
            for _ in 0..table.capacity { glyph_ids.extend_from_slice(&seed_glyphs); }
            Some(CompiledDataRegisterTable { id: table.id.clone(), register_width: table.register_width, atlas_page: table.atlas_page, glyph_ids })
        } else { None };
        if plan.recycling {
            if compiled_data_register_table.is_none() {
                anyhow::ensure!(plan.logical_data_ids.len() == logical_capacity && plan.logical_labels.len() == logical_capacity,
                                "recycling list {} logical data table disagrees with logical capacity", plan.id);
            }
            anyhow::ensure!(plan.initial_ring_slots == (0..physical_slots).collect::<Vec<_>>(),
                            "recycling list {} has non-canonical initial ring slots", plan.id);
        }
        anyhow::ensure!(plan.visible_rows > 0 && plan.visible_rows <= plan.capacity,
                        "virtual list {} visible_rows={} outside 1..={}", plan.id, plan.visible_rows, plan.capacity);
        anyhow::ensure!(plan.row_height > 0 && plan.viewport_height == plan.visible_rows * plan.row_height,
                        "virtual list {} viewport_height must equal visible_rows * row_height", plan.id);
        anyhow::ensure!(plan.row_ids.len() == plan.capacity && plan.row_layout_offsets.len() == plan.capacity,
                        "virtual list {} row plan length disagrees with capacity", plan.id);
        anyhow::ensure!(plan.row_instance_offsets.len() == plan.capacity && plan.row_glyph_slots.len() == plan.capacity,
                        "virtual list {} GPU row address table length disagrees with capacity", plan.id);
        anyhow::ensure!(plan.row_instance_offsets.iter().all(|offsets| !offsets.is_empty()),
                        "virtual list {} has a row with no compiler instance offsets", plan.id);
        anyhow::ensure!(plan.row_glyph_slots.iter().all(|slots| !slots.is_empty()),
                        "virtual list {} has a row with no compiler glyph slots", plan.id);
        anyhow::ensure!(plan.row_instance_offsets.iter().flatten().all(|offset| offset % std::mem::size_of::<QuadInstance>() == 0 && offset / std::mem::size_of::<QuadInstance>() < scene.resource_budget.instance_capacity),
                        "virtual list {} instance address exceeds compiler resource budget", plan.id);
        anyhow::ensure!(plan.row_glyph_slots.iter().flatten().all(|slot| *slot < scene.glyph_placement_plan.len()),
                        "virtual list {} glyph placement slot exceeds compiler resource budget", plan.id);
        anyhow::ensure!(plan.row_draw_ranges.len() == plan.capacity && plan.row_glyph_subranges.len() == plan.capacity,
                        "virtual list {} row subrange table length disagrees with capacity", plan.id);
        let mut previous_draw_end = 0u32;
        let mut previous_glyph_end = 0u32;
        for row in 0..plan.capacity {
            let mut instances = plan.row_instance_offsets[row].iter().map(|offset| (offset / std::mem::size_of::<QuadInstance>()) as u32).collect::<Vec<_>>();
            instances.sort_unstable();
            anyhow::ensure!(instances.windows(2).all(|pair| pair[1] == pair[0] + 1),
                            "virtual list {} row {} quad range is not contiguous", plan.id, row);
            let draw = &plan.row_draw_ranges[row];
            anyhow::ensure!(draw.count > 0 && draw.first == instances[0] && draw.count as usize == instances.len() && draw.first >= previous_draw_end,
                            "virtual list {} row {} draw range does not exactly cover compiler instances", plan.id, row);
            previous_draw_end = draw.first + draw.count;
            let mut glyphs = plan.row_glyph_slots[row].iter().map(|slot| *slot as u32).collect::<Vec<_>>();
            glyphs.sort_unstable();
            anyhow::ensure!(glyphs.windows(2).all(|pair| pair[1] == pair[0] + 1),
                            "virtual list {} row {} glyph subrange is not contiguous", plan.id, row);
            let glyph = &plan.row_glyph_subranges[row];
            anyhow::ensure!(glyph.count > 0 && glyph.first == glyphs[0] && glyph.count as usize == glyphs.len() && glyph.first >= previous_glyph_end,
                            "virtual list {} row {} glyph subrange does not exactly cover compiler placements", plan.id, row);
            previous_glyph_end = glyph.first + glyph.count;
        }
        anyhow::ensure!(plan.visible_row_tile_ids == (0..plan.visible_rows).collect::<Vec<_>>(),
                        "virtual list {} initial viewport must select canonical row-tile prefix", plan.id);
        let mut seen_rows = HashSet::new();
        for (row_id, expected_offset) in plan.row_ids.iter().zip(plan.row_layout_offsets.iter()) {
            anyhow::ensure!(seen_rows.insert(row_id.as_str()), "virtual list {} repeats row {}", plan.id, row_id);
            let layout = layout_by_id.get(row_id.as_str()).context("virtual-list row missing Layout Plan entry")?;
            anyhow::ensure!(layout._instance_offset == *expected_offset,
                            "virtual list {} row {} layout offset mismatch: compiler={} scene={}",
                            plan.id, row_id, layout._instance_offset, expected_offset);
        }
        anyhow::ensure!(plan.row_layout_offsets.windows(2).all(|pair| pair[0] < pair[1]),
                        "virtual list {} row instance offsets are not strictly ascending", plan.id);
        let max_scroll = logical_capacity - plan.visible_rows;
        if compiled_data_register_table.is_some() {
            anyhow::ensure!(plan.scroll_transitions.is_empty(), "compact data-register list {} unexpectedly serialized transition edges", plan.id);
        } else {
            anyhow::ensure!(plan.scroll_transitions.len() == max_scroll.saturating_mul(2),
                            "virtual list {} has {} scroll transitions; expected {} directed adjacent edges", plan.id, plan.scroll_transitions.len(), max_scroll.saturating_mul(2));
        }
        let list_layout = layout_by_id.get(plan.id.as_str()).with_context(|| format!("virtual list {} lacks layout entry", plan.id))?;
        let scroll_scissor = VirtualScrollScissor { x: (list_layout.ndc_pos[0] + 1.0) * canvas_width * 0.5, y: (1.0 - list_layout.ndc_pos[1] - list_layout.ndc_size[1]) * canvas_height * 0.5, width: list_layout.ndc_size[0] * canvas_width * 0.5, height: list_layout.ndc_size[1] * canvas_height * 0.5 };
        let row_base_instance_y = plan.row_instance_offsets.iter().map(|offsets| offsets.iter().map(|offset| {
            let layout = scene.layout_plan.iter().find(|entry| entry._instance_offset == *offset).expect("virtual-list instance offset admitted above"); layout.ndc_pos[1]
        }).collect::<Vec<_>>()).collect::<Vec<_>>();
        let row_base_glyph_y = plan.row_glyph_slots.iter().map(|slots| slots.iter().map(|slot| scene.glyph_placement_plan[*slot].ndc_pos[1]).collect::<Vec<_>>()).collect::<Vec<_>>();
        let mut transition_edges = HashSet::new();
        for transition in &plan.scroll_transitions {
            anyhow::ensure!(transition.from_slot <= max_scroll && transition.to_slot <= max_scroll && transition.from_slot.abs_diff(transition.to_slot) == 1,
                            "virtual list {} has non-adjacent scroll edge {} -> {}", plan.id, transition.from_slot, transition.to_slot);
            anyhow::ensure!(transition_edges.insert((transition.from_slot, transition.to_slot)),
                            "virtual list {} repeats scroll edge {} -> {}", plan.id, transition.from_slot, transition.to_slot);
            let expected_tiles = if plan.recycling {
                (transition.to_slot..transition.to_slot + plan.visible_rows).map(|logical| logical % physical_slots).collect::<Vec<_>>()
            } else {
                (transition.to_slot..transition.to_slot + plan.visible_rows).collect::<Vec<_>>()
            };
            anyhow::ensure!(transition.visible_row_tile_ids == expected_tiles,
                            "virtual list {} scroll edge {} -> {} has widened or incorrect row-tile range", plan.id, transition.from_slot, transition.to_slot);
            let first_row = transition.from_slot.min(transition.to_slot);
            let last_row = transition.from_slot.max(transition.to_slot) + plan.visible_rows - 1;
            let row_indices = if plan.recycling { (0..physical_slots).collect::<Vec<_>>() } else { (first_row..=last_row).collect::<Vec<_>>() };
            let mut expected_instance_offsets = row_indices.iter().flat_map(|row| plan.row_instance_offsets[*row].iter().map(|offset| offset + 4)).collect::<Vec<_>>();
            expected_instance_offsets.sort_unstable(); expected_instance_offsets.dedup();
            let mut actual_instance_offsets = transition.instance_y_patches.iter().map(|patch| patch.offset).collect::<Vec<_>>();
            actual_instance_offsets.sort_unstable(); actual_instance_offsets.dedup();
            anyhow::ensure!(actual_instance_offsets == expected_instance_offsets && transition.instance_y_patches.iter().all(|patch| patch.y.is_finite() && patch.y >= -3.0 && patch.y <= 1.0),
                            "virtual list {} scroll edge {} -> {} has invalid instance patch proof", plan.id, transition.from_slot, transition.to_slot);
            let mut expected_glyph_offsets = row_indices.iter().flat_map(|row| plan.row_glyph_slots[*row].iter().map(|slot| slot * GLYPH_PLACEMENT_BYTES + 4)).collect::<Vec<_>>();
            expected_glyph_offsets.sort_unstable(); expected_glyph_offsets.dedup();
            let mut actual_glyph_offsets = transition.glyph_y_patches.iter().map(|patch| patch.offset).collect::<Vec<_>>();
            actual_glyph_offsets.sort_unstable(); actual_glyph_offsets.dedup();
            anyhow::ensure!(actual_glyph_offsets == expected_glyph_offsets && transition.glyph_y_patches.iter().all(|patch| patch.y.is_finite() && patch.y >= -3.0 && patch.y <= 1.0),
                            "virtual list {} scroll edge {} -> {} has invalid glyph patch proof", plan.id, transition.from_slot, transition.to_slot);
            if plan.recycling {
                let encode_ascii = |text: &str, count: usize| -> Vec<u32> {
                    let mut glyphs = text.chars().map(|ch| match ch {
                        ' ' => 1u32 << 16,
                        'A'..='Z' => (1u32 << 16) | (1 + (ch as u32 - 'A' as u32)),
                        _ => panic!("compiler admitted non-ASCII-uppercase recycling data"),
                    }).collect::<Vec<_>>();
                    glyphs.resize(count, 1u32 << 16);
                    glyphs
                };
                let mut expected_glyph_ids = Vec::new();
                for physical_slot in 0..physical_slots {
                    let logical_index = transition.to_slot + ((physical_slot + physical_slots - (transition.to_slot % physical_slots)) % physical_slots);
                    let glyphs = if logical_index < logical_capacity {
                        encode_ascii(&plan.logical_labels[logical_index], plan.row_glyph_slots[physical_slot].len())
                    } else {
                        vec![1u32 << 16; plan.row_glyph_slots[physical_slot].len()]
                    };
                    expected_glyph_ids.extend(plan.row_glyph_slots[physical_slot].iter().zip(glyphs.iter()).map(|(slot, glyph_id)| (slot * GLYPH_CELL_BYTES, *glyph_id)));
                }
                expected_glyph_ids.sort_unstable(); expected_glyph_ids.dedup();
                let mut actual_glyph_ids = transition.glyph_id_patches.iter().map(|patch| (patch.offset, patch.glyph_id)).collect::<Vec<_>>();
                actual_glyph_ids.sort_unstable(); actual_glyph_ids.dedup();
                anyhow::ensure!(actual_glyph_ids == expected_glyph_ids,
                                "recycling list {} scroll edge {} -> {} has invalid glyph data-binding patch proof", plan.id, transition.from_slot, transition.to_slot);
            } else {
                anyhow::ensure!(transition.glyph_id_patches.is_empty(), "static virtual list {} unexpectedly carries data-binding patches", plan.id);
            }
            let expected_scissor_x = (list_layout.ndc_pos[0] + 1.0) * canvas_width * 0.5;
            let expected_scissor_y = (1.0 - list_layout.ndc_pos[1] - list_layout.ndc_size[1]) * canvas_height * 0.5;
            let expected_scissor_width = list_layout.ndc_size[0] * canvas_width * 0.5;
            let expected_scissor_height = list_layout.ndc_size[1] * canvas_height * 0.5;
            anyhow::ensure!((transition.scissor.x - expected_scissor_x).abs() < 0.001 && (transition.scissor.y - expected_scissor_y).abs() < 0.001 && (transition.scissor.width - expected_scissor_width).abs() < 0.001 && (transition.scissor.height - expected_scissor_height).abs() < 0.001,
                            "virtual list {} scroll edge {} -> {} has non-canonical scissor", plan.id, transition.from_slot, transition.to_slot);
        }
        let admitted_batches = plan.data_update_batches.clone();
        if let Some(table) = compiled_data_register_table.as_ref() {
            let mut batch_ids = HashSet::new();
            for batch in &admitted_batches {
                anyhow::ensure!(batch_ids.insert(batch.id.as_str()) && batch.table == table.id && !batch.updates.is_empty(),
                                "virtual list {} has invalid data-update-batch table binding or duplicate ID", plan.id);
                let mut indices = HashSet::new();
                for update in &batch.updates {
                    anyhow::ensure!(indices.insert(update.index) && update.index < logical_capacity,
                                    "data-update-batch {} violates fixed logical index proof", batch.id);
                    compact_register_glyphs(&update.value, table.register_width, table.atlas_page)
                        .with_context(|| format!("data-update-batch {} violates fixed legacy glyph domain/width proof", batch.id))?;
                }
            }
        } else {
            anyhow::ensure!(admitted_batches.is_empty(), "virtual list {} exports batches without a compact data-register-table", plan.id);
        }
        compiled.push(CompiledVirtualListPlan {
            id: plan.id.clone(), capacity: plan.capacity, logical_capacity, physical_slots, recycling: plan.recycling,
            logical_data_ids: plan.logical_data_ids.clone(), logical_labels: plan.logical_labels.clone(), ring_slots: if plan.recycling { plan.initial_ring_slots.clone() } else { (0..plan.capacity).collect() }, data_register_table: compiled_data_register_table, data_update_batches: admitted_batches, visible_rows: plan.visible_rows,
            row_height: plan.row_height, viewport_height: plan.viewport_height,
            row_layout_offsets: plan.row_layout_offsets.clone(),
            row_instance_offsets: plan.row_instance_offsets.clone(),
            row_glyph_slots: plan.row_glyph_slots.clone(),
            row_draw_ranges: plan.row_draw_ranges.clone(),
            row_glyph_subranges: plan.row_glyph_subranges.clone(),
            row_base_instance_y, row_base_glyph_y, scroll_scissor,
            visible_row_tile_ids: plan.visible_row_tile_ids.clone(),
            scroll_transitions: plan.scroll_transitions.clone(),
            current_viewport_slot: 0,
        });
    }
    Ok(compiled)
}

fn compiler_list_interaction_plans(scene: &Scene, lists: &[CompiledVirtualListPlan]) -> Result<Vec<CompiledListInteractionPlan>> {
    anyhow::ensure!(scene.list_interaction_plans.len() == lists.len(), "list_interaction_plans must exactly cover virtual_list_plans");
    let mut compiled = Vec::with_capacity(lists.len());
    for (index, (artifact, list)) in scene.list_interaction_plans.iter().zip(lists.iter()).enumerate() {
        anyhow::ensure!(artifact.id == list.id && artifact.logical_capacity == list.logical_capacity && artifact.physical_slots == list.physical_slots && artifact.visible_rows == list.visible_rows && artifact.row_height == list.row_height,
                        "list interaction {} disagrees with virtual-list compiler artifact", artifact.id);
        anyhow::ensure!(artifact.row_color_offsets.len() == list.physical_slots && artifact.navigation.up_delta == -1 && artifact.navigation.down_delta == 1 && artifact.navigation.minimum_logical_row == 0 && artifact.navigation.maximum_logical_row + 1 == list.logical_capacity,
                        "list interaction {} has invalid fixed navigation or row color table", artifact.id);
        let expected = list.row_layout_offsets.iter().map(|offset| offset + 16).collect::<Vec<_>>();
        anyhow::ensure!(artifact.row_color_offsets == expected && artifact.render.packet_worklist_index == RenderRequest::NO_PACKETS && artifact.render.viewport_only && artifact.render.row_tile_rule == "logical-mod-physical-slots",
                        "list interaction {} widened physical patch or renderer scope", artifact.id);
        compiled.push(CompiledListInteractionPlan { list_index: index, row_color_offsets: expected, hover_color: artifact.hover_color, selected_color: artifact.selected_color, minimum_logical_row: artifact.navigation.minimum_logical_row, maximum_logical_row: artifact.navigation.maximum_logical_row });
    }
    Ok(compiled)
}

fn compiler_scrollbar_plans(
    scene: &Scene,
    lists: &[CompiledVirtualListPlan],
    packet_worklists: &[CompiledPacketWorklist],
) -> Result<Vec<CompiledScrollbarPlan>> {
    let visual_canvas = compiler_visual_language_plan(scene)?;
    let canvas_width = visual_canvas.width as f32;
    let canvas_height = visual_canvas.height as f32;
    let layouts = scene.layout_plan.iter().map(|layout| (layout.id.as_str(), layout)).collect::<HashMap<_, _>>();
    let mut seen_ids = HashSet::new();
    let mut seen_lists = HashSet::new();
    let mut seen_thumb_offsets = HashSet::new();
    let mut compiled = Vec::with_capacity(scene.scrollbar_plans.len());
    for artifact in &scene.scrollbar_plans {
        anyhow::ensure!(artifact.abi_schema == SCROLLBAR_PLAN_ABI_SCHEMA && artifact.abi_revision == SCROLLBAR_PLAN_ABI_REVISION,
                        "scrollbar {} has unsupported ABI {}@{}", artifact.id, artifact.abi_schema, artifact.abi_revision);
        anyhow::ensure!(seen_ids.insert(artifact.id.as_str()) && seen_lists.insert(artifact.list_id.as_str()),
                        "scrollbar {} duplicates its ID or virtual list binding", artifact.id);
        let list_index = lists.iter().position(|list| list.id == artifact.list_id)
            .with_context(|| format!("scrollbar {} refers to unknown virtual list {}", artifact.id, artifact.list_id))?;
        let list = &lists[list_index];
        anyhow::ensure!(list.data_register_table.is_some(),
                        "scrollbar {} requires compact direct-scroll virtual list {} in ABI v1", artifact.id, artifact.list_id);
        anyhow::ensure!(artifact.physical_slot_rule == "logical-mod-physical-slots"
                        && artifact.max_viewport == list.logical_capacity - list.visible_rows,
                        "scrollbar {} disagrees with frozen virtual list viewport/ring ABI", artifact.id);
        anyhow::ensure!(artifact.packet_worklist_index == RenderRequest::NO_PACKETS
                        && packet_worklists.get(artifact.packet_worklist_index).map(|worklist| worklist.packet_indices.is_empty()).unwrap_or(false),
                        "scrollbar {} widened packet worklist", artifact.id);
        let schedule = scene.render_schedules.first().context("scrollbar ABI requires one compiler render schedule")?;
        let intersects = |tile: &ScissorTile| -> bool {
            artifact.track.x < tile.x + tile.width && artifact.track.x + artifact.track.width > tile.x
                && artifact.track.y < tile.y + tile.height && artifact.track.y + artifact.track.height > tile.y
        };
        let expected_tile_ids = schedule.tiles.iter().enumerate().filter_map(|(index, tile)| intersects(tile).then_some(index)).collect::<Vec<_>>();
        anyhow::ensure!(!artifact.tile_ids.is_empty() && artifact.tile_ids == expected_tile_ids && artifact.tile_ids.windows(2).all(|pair| pair[0] < pair[1]),
                        "scrollbar {} has widened or incorrect compiler tile scope", artifact.id);
        let tile_mask = artifact.tile_ids.iter().fold(0u64, |mask, tile_id| mask | (1u64 << tile_id));
        anyhow::ensure!(artifact.track.width.is_finite() && artifact.track.height.is_finite()
                        && artifact.track.x.is_finite() && artifact.track.y.is_finite()
                        && artifact.track.width > 0.0 && artifact.track.height > 0.0
                        && artifact.thumb_height.is_finite() && artifact.thumb_height > 0.0
                        && artifact.thumb_height <= artifact.track.height && artifact.max_viewport > 0,
                        "scrollbar {} has invalid fixed geometry or viewport domain", artifact.id);
        let track = layouts.get(artifact.track_id.as_str())
            .with_context(|| format!("scrollbar {} missing track layout {}", artifact.id, artifact.track_id))?;
        let thumb = layouts.get(artifact.thumb_id.as_str())
            .with_context(|| format!("scrollbar {} missing thumb layout {}", artifact.id, artifact.thumb_id))?;
        anyhow::ensure!(track.tag == "scrollbar" && thumb.tag == "scrollbar-thumb"
                        && track._instance_offset == artifact.track_instance_offset
                        && thumb._instance_offset == artifact.thumb_instance_offset
                        && artifact.thumb_instance_offset % std::mem::size_of::<QuadInstance>() == 0
                        && artifact.thumb_instance_offset / std::mem::size_of::<QuadInstance>() < scene.resource_budget.instance_capacity
                        && seen_thumb_offsets.insert(artifact.thumb_instance_offset),
                        "scrollbar {} has invalid fixed track/thumb instance address", artifact.id);
        let layout_rect = |entry: &LayoutEntry| -> (f32, f32, f32, f32) {
            ((entry.ndc_pos[0] + 1.0) * canvas_width * 0.5,
             (1.0 - entry.ndc_pos[1] - entry.ndc_size[1]) * canvas_height * 0.5,
             entry.ndc_size[0] * canvas_width * 0.5,
             entry.ndc_size[1] * canvas_height * 0.5)
        };
        let (track_x, track_y, track_width, track_height) = layout_rect(track);
        let (thumb_x, thumb_y, thumb_width, thumb_height) = layout_rect(thumb);
        anyhow::ensure!((track_x - artifact.track.x).abs() < 0.001 && (track_y - artifact.track.y).abs() < 0.001
                        && (track_width - artifact.track.width).abs() < 0.001 && (track_height - artifact.track.height).abs() < 0.001
                        && (thumb_x - artifact.track.x).abs() < 0.001 && (thumb_y - artifact.track.y).abs() < 0.001
                        && (thumb_width - artifact.track.width).abs() < 0.001 && (thumb_height - artifact.thumb_height).abs() < 0.001,
                        "scrollbar {} track/thumb layout geometry disagrees with compiler artifact", artifact.id);
        println!("compiler scrollbar: id={} list={} track={}x{}+{},{} thumb-height={} max-viewport={} tiles={:?} worklist={}",
                 artifact.id, artifact.list_id, artifact.track.width, artifact.track.height, artifact.track.x, artifact.track.y,
                 artifact.thumb_height, artifact.max_viewport, artifact.tile_ids, artifact.packet_worklist_index);
        compiled.push(CompiledScrollbarPlan {
            id: artifact.id.clone(), list_index, thumb_instance_offset: artifact.thumb_instance_offset,
            track_x: artifact.track.x, track_y: artifact.track.y,
            track_width: artifact.track.width, track_height: artifact.track.height,
            thumb_height: artifact.thumb_height, max_viewport: artifact.max_viewport,
            tile_ids: artifact.tile_ids.clone(), tile_mask,
        });
    }
    Ok(compiled)
}

fn compiler_list_navigation_plans(
    scene: &Scene,
    lists: &[CompiledVirtualListPlan],
    scrollbars: &[CompiledScrollbarPlan],
    packet_worklists: &[CompiledPacketWorklist],
) -> Result<Vec<CompiledListNavigationPlan>> {
    let expected_transitions = [
        ("page-up", "subtract-step"),
        ("page-down", "add-step-clamp"),
        ("home", "set-zero"),
        ("end", "set-max"),
    ];
    let mut seen_ids = HashSet::new();
    let mut seen_lists = HashSet::new();
    let mut compiled = Vec::with_capacity(scene.list_navigation_plans.len());
    for artifact in &scene.list_navigation_plans {
        anyhow::ensure!(artifact.abi_schema == LIST_NAVIGATION_PLAN_ABI_SCHEMA && artifact.abi_revision == LIST_NAVIGATION_PLAN_ABI_REVISION,
                        "list navigation {} has unsupported ABI {}@{}", artifact.id, artifact.abi_schema, artifact.abi_revision);
        anyhow::ensure!(seen_ids.insert(artifact.id.as_str()) && seen_lists.insert(artifact.list_id.as_str()),
                        "list navigation {} duplicates its ID or virtual list binding", artifact.id);
        let list_index = lists.iter().position(|list| list.id == artifact.list_id)
            .with_context(|| format!("list navigation {} refers to unknown virtual list {}", artifact.id, artifact.list_id))?;
        let list = &lists[list_index];
        anyhow::ensure!(list.data_register_table.is_some()
                        && artifact.page_step == list.visible_rows
                        && artifact.max_viewport == list.logical_capacity - list.visible_rows
                        && artifact.max_viewport > 0
                        && artifact.physical_slot_rule == "logical-mod-physical-slots",
                        "list navigation {} disagrees with frozen virtual list geometry/ring ABI", artifact.id);
        let scrollbar = scrollbars.iter().find(|scrollbar| scrollbar.id == artifact.scrollbar_id)
            .with_context(|| format!("list navigation {} refers to unknown scrollbar {}", artifact.id, artifact.scrollbar_id))?;
        anyhow::ensure!(scrollbar.list_index == list_index && artifact.tile_ids == scrollbar.tile_ids,
                        "list navigation {} disagrees with bound scrollbar tile scope", artifact.id);
        anyhow::ensure!(artifact.packet_worklist_index == RenderRequest::NO_PACKETS
                        && packet_worklists.get(artifact.packet_worklist_index).map(|worklist| worklist.packet_indices.is_empty()).unwrap_or(false),
                        "list navigation {} widened packet worklist", artifact.id);
        let actual = artifact.transitions.iter().map(|transition| (transition.key.as_str(), transition.kind.as_str())).collect::<Vec<_>>();
        anyhow::ensure!(actual.as_slice() == expected_transitions,
                        "list navigation {} transition table is not canonical PageUp/PageDown/Home/End", artifact.id);
        println!("compiler list navigation: id={} list={} scrollbar={} page-step={} max-viewport={} tiles={:?} worklist={}",
                 artifact.id, artifact.list_id, artifact.scrollbar_id, artifact.page_step,
                 artifact.max_viewport, artifact.tile_ids, artifact.packet_worklist_index);
        compiled.push(CompiledListNavigationPlan { id: artifact.id.clone(), list_index, page_step: artifact.page_step,
                                                    max_viewport: artifact.max_viewport, tile_mask: scrollbar.tile_mask });
    }
    Ok(compiled)
}

fn compiler_navigation_selection_plan(
    scene: &Scene,
    state_slot_ids: &[String],
    action_slot_ids: &[String],
    action_tile_masks: &HashMap<String, u64>,
    event_tile_masks: &[EventTileMasks],
    packet_worklists: &[CompiledPacketWorklist],
) -> Result<Option<CompiledNavigationSelectionPlan>> {
    let Some(plan) = &scene.navigation_selection_plan else {
        let material_rail_declared = scene.layout_plan.iter().any(|entry| entry.id == "material-nav-rail");
        anyhow::ensure!(!material_rail_declared,
                        "desktop-wide visual Scene with material-nav-rail may not disable navigation_selection_plan v1");
        println!("compiler navigation selection: disabled destinations=0");
        return Ok(None);
    };
    anyhow::ensure!(plan.abi_schema == NAVIGATION_SELECTION_PLAN_ABI_SCHEMA
                    && plan.abi_revision == NAVIGATION_SELECTION_PLAN_ABI_REVISION,
                    "navigation selection has unsupported ABI {}@{}", plan.abi_schema, plan.abi_revision);
    anyhow::ensure!((3..=7).contains(&plan.destinations.len()),
                    "navigation selection {} must have 3..7 fixed destinations", plan.rail_id);
    anyhow::ensure!(plan.state_index < state_slot_ids.len() && state_slot_ids[plan.state_index] == plan.state,
                    "navigation selection {} state slot disagrees with compiler State Slot table", plan.rail_id);
    let state_slot = scene.state_slots.get(plan.state_index)
        .with_context(|| format!("navigation selection {} state slot is absent", plan.rail_id))?;
    anyhow::ensure!(state_slot.id == plan.state && state_slot.initial == plan.initial_value,
                    "navigation selection {} initial state proof disagrees", plan.rail_id);
    anyhow::ensure!(packet_worklists.get(RenderRequest::NO_PACKETS)
                    .map(|worklist| worklist.packet_indices.is_empty()).unwrap_or(false),
                    "navigation selection requires compiler no-packets worklist");
    let mut seen_ids = HashSet::new();
    let mut seen_events = HashSet::new();
    let mut seen_actions = HashSet::new();
    let mut seen_offsets = HashSet::new();
    let mut compiled = Vec::with_capacity(plan.destinations.len());
    for (index, destination) in plan.destinations.iter().enumerate() {
        anyhow::ensure!(destination.target_value == index as i64
                        && seen_ids.insert(destination.id.as_str())
                        && seen_events.insert(destination.event_node.as_str())
                        && seen_actions.insert(destination.action.as_str())
                        && seen_offsets.insert(destination.instance_offset),
                        "navigation selection {} has duplicate or non-canonical destination transition", plan.rail_id);
        anyhow::ensure!(destination.action_slot_index < action_slot_ids.len()
                        && action_slot_ids[destination.action_slot_index] == destination.action,
                        "navigation destination {} action slot disagrees", destination.id);
        let action = scene.actions.get(&destination.action)
            .with_context(|| format!("navigation destination {} references unknown action {}", destination.id, destination.action))?;
        anyhow::ensure!(action.action_index == destination.action_slot_index
                        && action.writes.len() == 1
                        && action.writes[0].state == plan.state
                        && action.writes[0].state_index == plan.state_index
                        && action.writes[0].op == "set"
                        && action.writes[0].value == destination.target_value
                        && action.gpu_updates.is_empty()
                        && action.instance_updates.is_empty(),
                        "navigation destination {} action is not a closed literal state selection", destination.id);
        let source = scene.layout_plan.iter().find(|layout| layout.id == destination.id)
            .with_context(|| format!("navigation destination {} source layout is absent", destination.id))?;
        anyhow::ensure!(source.tag == "stack" && source._instance_offset == destination.instance_offset
                        && destination.instance_offset > 0
                        && destination.instance_offset % std::mem::size_of::<QuadInstance>() == 0
                        && destination.instance_offset / std::mem::size_of::<QuadInstance>() < scene.resource_budget.instance_capacity,
                        "navigation destination {} source instance witness is invalid", destination.id);
        anyhow::ensure!(destination.selected_color.iter().chain(destination.unselected_color.iter()).all(|value| value.is_finite() && (0.0..=1.0).contains(value)),
                        "navigation destination {} has noncanonical RGBA", destination.id);
        let is_initial = destination.id == plan.initial_destination;
        anyhow::ensure!(source.color == if is_initial { destination.selected_color } else { destination.unselected_color },
                        "navigation destination {} initial source color disagrees with selection state", destination.id);
        let event_slot = scene.event_map.iter().position(|event| event.node == destination.event_node)
            .with_context(|| format!("navigation destination {} event target is absent", destination.id))?;
        let event = &scene.event_map[event_slot];
        let source_x = (source.ndc_pos[0] + 1.0) * scene.visual_language_plan.canvas.width * 0.5;
        let source_y = (1.0 - source.ndc_pos[1] - source.ndc_size[1]) * scene.visual_language_plan.canvas.height * 0.5;
        let source_width = source.ndc_size[0] * scene.visual_language_plan.canvas.width * 0.5;
        let source_height = source.ndc_size[1] * scene.visual_language_plan.canvas.height * 0.5;
        anyhow::ensure!(event._action.as_deref() == Some(destination.action.as_str())
                        && event.action_index == Some(destination.action_slot_index)
                        && event.instance_offset % std::mem::size_of::<QuadInstance>() == 0
                        && (event.x - source_x).abs() < 0.001
                        && (event.y - source_y).abs() < 0.001
                        && (event.width - source_width).abs() < 0.001
                        && (event.height - source_height).abs() < 0.001,
                        "navigation destination {} event geometry/action disagrees with source layout", destination.id);
        anyhow::ensure!(event.base_color == [0.0, 0.0, 0.0, 0.0],
                        "navigation destination {} hit target must remain transparent", destination.id);
        let tile_mask = tile_mask(&destination.tile_ids, scene.render_schedules[0].tiles.len(), &format!("navigation destination {}", destination.id))?;
        anyhow::ensure!(tile_mask != 0
                        && action_tile_masks.get(&destination.action).copied() == Some(tile_mask)
                        && event_tile_masks.get(event_slot).map(|masks| masks.release == tile_mask).unwrap_or(false),
                        "navigation destination {} widened or mismatched local tile scope", destination.id);
        compiled.push(CompiledNavigationSelectionDestination {
            id: destination.id.clone(), event_slot, action_slot_index: destination.action_slot_index,
            target_value: destination.target_value, instance_offset: destination.instance_offset,
            selected_color: destination.selected_color, unselected_color: destination.unselected_color, tile_mask,
        });
    }
    let selected_index = usize::try_from(plan.initial_value).context("navigation selection initial value is negative")?;
    anyhow::ensure!(selected_index < compiled.len() && compiled[selected_index].id == plan.initial_destination,
                    "navigation selection initial destination/value disagree");
    println!("compiler navigation selection: rail={} state={} slot={} destinations={} initial={} tiles={:?} no-packets",
             plan.rail_id, plan.state, plan.state_index, compiled.len(), plan.initial_destination,
             compiled.iter().map(|entry| entry.tile_mask).collect::<Vec<_>>());
    Ok(Some(CompiledNavigationSelectionPlan { rail_id: plan.rail_id.clone(), state_index: plan.state_index, destinations: compiled, selected_index }))
}

fn compiler_material_observability_workbench_plan(
    scene: &Scene,
    state_slot_ids: &[String],
    navigation_selection_plan: &Option<CompiledNavigationSelectionPlan>,
    virtual_lists: &[CompiledVirtualListPlan],
    log_browser_plans: &[CompiledLogBrowserPlan],
    instances: &[QuadInstance],
    placements: &[GlyphPlacementInstance],
) -> Result<Option<CompiledMaterialObservabilityWorkbenchPlan>> {
    let Some(plan) = &scene.material_observability_workbench_plan else {
        anyhow::ensure!(!scene.material_observability_workbench_required,
                        "Scene marked material_observability_workbench_required may not disable material_observability_workbench_plan v1");
        println!("compiler material workbench: disabled views=0");
        return Ok(None);
    };
    anyhow::ensure!(plan.abi_schema == MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_SCHEMA
                    && plan.abi_revision == MATERIAL_OBSERVABILITY_WORKBENCH_PLAN_ABI_REVISION,
                    "material workbench has unsupported ABI {}@{}", plan.abi_schema, plan.abi_revision);
    anyhow::ensure!(scene.material_observability_workbench_required,
                    "material workbench plan may not be present without its explicit required marker");
    anyhow::ensure!(plan.views.len() == 3, "material workbench {} must have exactly three fixed view endpoints", plan.id);
    anyhow::ensure!(plan.state_index < state_slot_ids.len() && state_slot_ids[plan.state_index] == plan.state,
                    "material workbench {} has invalid State Slot witness", plan.id);
    let state_slot = scene.state_slots.get(plan.state_index)
        .with_context(|| format!("material workbench {} State Slot is absent", plan.id))?;
    anyhow::ensure!(state_slot.id == plan.state && state_slot.initial == plan.initial_value,
                    "material workbench {} initial State Slot endpoint disagrees", plan.id);
    let navigation = navigation_selection_plan.as_ref().context("material workbench requires admitted navigation_selection_plan")?;
    anyhow::ensure!(navigation.rail_id == plan.rail_id && navigation.state_index == plan.state_index
                    && navigation.destinations.len() == plan.views.len() && navigation.selected_index == plan.initial_value as usize,
                    "material workbench {} rail/state endpoint disagrees with navigation selection plan", plan.id);
    anyhow::ensure!(scene.render_schedules.len() == 1, "material workbench requires one fixed render schedule");
    let tiles = &scene.render_schedules[0].tiles;
    let canvas = &scene.visual_language_plan.canvas;
    let layout_by_offset = scene.layout_plan.iter().map(|layout| (layout._instance_offset, layout)).collect::<HashMap<_, _>>();
    let mut seen_view_ids = HashSet::new();
    let mut seen_destinations = HashSet::new();
    let mut seen_offsets = HashSet::new();
    let mut seen_glyph_slots = HashSet::new();
    let mut seen_event_slots = HashSet::new();
    let mut seen_shadow_indices = HashSet::new();
    let mut view_for_event_slot = vec![None; scene.event_map.len()];
    let mut compiled = Vec::with_capacity(plan.views.len());
    for (index, view) in plan.views.iter().enumerate() {
        anyhow::ensure!(view.target_value == index as i64
                        && seen_view_ids.insert(view.view_root_id.as_str())
                        && seen_destinations.insert(view.destination_id.as_str()),
                        "material workbench {} has duplicate or noncanonical view endpoint", plan.id);
        anyhow::ensure!(view.node_ids.first().map(String::as_str) == Some(view.view_root_id.as_str())
                        && view.node_ids.get(1..).is_some_and(|tail| tail.windows(2).all(|pair| pair[0] < pair[1]))
                        && scene.layout_plan.iter().any(|layout| layout.id == view.view_root_id && layout.tag == "stack"),
                        "material workbench view {} has invalid canonical static subtree witness", view.view_root_id);
        let node_set = view.node_ids.iter().collect::<HashSet<_>>();
        let mut expected_offsets = scene.layout_plan.iter().filter(|layout| node_set.contains(&layout.id))
            .map(|layout| layout._instance_offset).collect::<Vec<_>>();
        expected_offsets.sort_unstable(); expected_offsets.dedup();
        anyhow::ensure!(view.instance_offsets == expected_offsets && view.instance_offsets.len() == view.instance_alphas.len()
                        && view.instance_offsets.iter().all(|offset| *offset > 0 && *offset % std::mem::size_of::<QuadInstance>() == 0
                                                           && *offset / std::mem::size_of::<QuadInstance>() < instances.len()),
                        "material workbench view {} instance address set is not its canonical subtree", view.view_root_id);
        let expected_alphas = view.instance_offsets.iter().map(|offset| layout_by_offset[offset].color[3]).collect::<Vec<_>>();
        anyhow::ensure!(view.instance_alphas.iter().zip(expected_alphas.iter()).all(|(actual, expected)| actual.is_finite() && (*actual - *expected).abs() <= 1e-6),
                        "material workbench view {} instance alpha endpoint disagrees with layout", view.view_root_id);
        let mut expected_glyph_slots = scene.glyph_placement_plan.iter().filter(|placement| node_set.contains(&placement.node))
            .map(|placement| placement.slot).collect::<Vec<_>>();
        expected_glyph_slots.sort_unstable(); expected_glyph_slots.dedup();
        anyhow::ensure!(view.glyph_slots == expected_glyph_slots && !view.glyph_slots.is_empty()
                        && view.glyph_slots.iter().all(|slot| *slot < placements.len()),
                        "material workbench view {} glyph address set is not its canonical subtree", view.view_root_id);
        let mut expected_event_slots = scene.event_map.iter().filter(|event| node_set.contains(&event.node))
            .map(|event| event.slot).collect::<Vec<_>>();
        expected_event_slots.sort_unstable(); expected_event_slots.dedup();
        anyhow::ensure!(view.event_slots == expected_event_slots
                        && view.event_slots.iter().all(|slot| *slot < scene.event_map.len() && scene.event_map[*slot].slot == *slot),
                        "material workbench view {} Event Map set is not its canonical subtree", view.view_root_id);
        let mut expected_tile_ids = Vec::new();
        for (tile_index, tile) in tiles.iter().enumerate() {
            let intersects = scene.layout_plan.iter().filter(|layout| node_set.contains(&layout.id)).any(|layout| {
                let x = (layout.ndc_pos[0] + 1.0) * canvas.width * 0.5;
                let y = (1.0 - layout.ndc_pos[1] - layout.ndc_size[1]) * canvas.height * 0.5;
                let width = layout.ndc_size[0] * canvas.width * 0.5;
                let height = layout.ndc_size[1] * canvas.height * 0.5;
                x < tile.x + tile.width && tile.x < x + width && y < tile.y + tile.height && tile.y < y + height
            });
            if intersects { expected_tile_ids.push(tile_index); }
        }
        anyhow::ensure!(view.tile_ids == expected_tile_ids && !view.tile_ids.is_empty(),
                        "material workbench view {} tile scope is not its canonical static subtree union", view.view_root_id);
        let tile_mask = tile_mask(&view.tile_ids, tiles.len(), &format!("material workbench view {}", view.view_root_id))?;
        let shadow_indices = scene.shadow_surface_plan.as_ref().map(|shadow_plan| {
            shadow_plan.layers.iter().enumerate()
                .filter_map(|(shadow_index, layer)| view.instance_offsets.contains(&layer.source_instance_offset).then_some(shadow_index))
                .collect::<Vec<_>>()
        }).unwrap_or_default();
        anyhow::ensure!(shadow_indices.windows(2).all(|pair| pair[0] < pair[1]),
                        "material workbench view {} shadow layer set is not canonical", view.view_root_id);
        let shadow_alphas = scene.shadow_surface_plan.as_ref().map(|shadow_plan| {
            shadow_indices.iter().map(|index| shadow_plan.layers[*index].opacity).collect::<Vec<_>>()
        }).unwrap_or_default();
        anyhow::ensure!(shadow_alphas.iter().all(|alpha| alpha.is_finite() && (0.0..=1.0).contains(alpha)),
                        "material workbench view {} shadow alpha endpoint is invalid", view.view_root_id);
        let navigation_destination = navigation.destinations.get(index).context("material workbench navigation endpoint is absent")?;
        anyhow::ensure!(navigation_destination.id == view.destination_id
                        && navigation_destination.event_slot == view.event_slot
                        && navigation_destination.target_value == view.target_value,
                        "material workbench view {} does not pair to the canonical rail destination", view.view_root_id);
        for &offset in &view.instance_offsets { anyhow::ensure!(seen_offsets.insert(offset), "material workbench view {} aliases another view instance offset", view.view_root_id); }
        for &slot in &view.glyph_slots { anyhow::ensure!(seen_glyph_slots.insert(slot), "material workbench view {} aliases another view glyph slot", view.view_root_id); }
        for &slot in &view.event_slots {
            anyhow::ensure!(seen_event_slots.insert(slot) && view_for_event_slot[slot].replace(index).is_none(),
                            "material workbench view {} aliases another view Event Map slot", view.view_root_id);
        }
        for &shadow_index in &shadow_indices {
            anyhow::ensure!(seen_shadow_indices.insert(shadow_index),
                            "material workbench view {} aliases another view shadow layer", view.view_root_id);
        }
        compiled.push(CompiledMaterialObservabilityWorkbenchView {
            destination_id: view.destination_id.clone(), event_slot: view.event_slot, target_value: view.target_value,
            view_root_id: view.view_root_id.clone(), instance_offsets: view.instance_offsets.clone(),
            instance_alphas: view.instance_alphas.clone(), glyph_slots: view.glyph_slots.clone(),
            event_slots: view.event_slots.clone(), shadow_indices, shadow_alphas, tile_mask,
        });
    }
    anyhow::ensure!(compiled.get(plan.initial_value as usize).is_some_and(|view| view.destination_id == plan.initial_view),
                    "material workbench {} initial destination/value disagree", plan.id);
    let systems_view_index = compiled.iter().position(|view| view.view_root_id == plan.systems_view_id)
        .with_context(|| format!("material workbench {} systems_view_id {} is not one of its fixed views", plan.id, plan.systems_view_id))?;
    let systems_view_wire = &plan.views[systems_view_index];
    anyhow::ensure!(systems_view_wire.node_ids.iter().any(|node| node == &plan.systems_list_id),
                    "material workbench {} systems list {} is not owned by its systems view", plan.id, plan.systems_list_id);
    anyhow::ensure!(virtual_lists.len() == 1 && log_browser_plans.len() == 1,
                    "material workbench {} requires exactly one virtual list and one log-browser plan", plan.id);
    let systems_list_index = virtual_lists.iter().position(|list| list.id == plan.systems_list_id)
        .with_context(|| format!("material workbench {} systems list {} is absent", plan.id, plan.systems_list_id))?;
    anyhow::ensure!(virtual_lists[systems_list_index].logical_capacity == 10_000
                    && virtual_lists[systems_list_index].physical_slots == 4
                    && log_browser_plans[0].list_index == systems_list_index,
                    "material workbench {} Systems arena must remain the admitted 10000x4 log viewport", plan.id);
    println!("compiler material workbench: v1 id={} rail={} views=3 selected={} systems-view={} fixed-alpha-lanes={} glyph-alpha-lanes={} no-runtime-routing",
             plan.id, plan.rail_id, plan.initial_view, plan.systems_view_id,
             compiled.iter().map(|view| view.instance_offsets.len()).sum::<usize>(),
             compiled.iter().map(|view| view.glyph_slots.len()).sum::<usize>());
    Ok(Some(CompiledMaterialObservabilityWorkbenchPlan {
        id: plan.id.clone(), rail_id: plan.rail_id.clone(), state_index: plan.state_index,
        systems_list_index, systems_view_index, selected_index: plan.initial_value as usize,
        views: compiled, view_for_event_slot,
    }))
}

fn apply_material_observability_workbench_initial_visibility(
    plan: &Option<CompiledMaterialObservabilityWorkbenchPlan>,
    instances: &mut [QuadInstance],
    placements: &mut [GlyphPlacementInstance],
    shadow_instances: &mut [QuadInstance],
    queue: &wgpu::Queue,
    instance_buffer: &wgpu::Buffer,
) {
    let Some(plan) = plan else { return; };
    let mut hidden_instance_lanes = 0usize;
    let mut hidden_glyph_lanes = 0usize;
    let mut hidden_shadow_lanes = 0usize;
    for (index, view) in plan.views.iter().enumerate() {
        if index == plan.selected_index { continue; }
        for &offset in &view.instance_offsets {
            let slot = offset / std::mem::size_of::<QuadInstance>();
            instances[slot].color[3] = 0.0;
            queue.write_buffer(instance_buffer, (offset + 28) as u64, bytemuck::bytes_of(&0.0f32));
            hidden_instance_lanes += 1;
        }
        for &slot in &view.glyph_slots {
            placements[slot].alpha = 0.0;
            hidden_glyph_lanes += 1;
        }
        for &shadow_index in &view.shadow_indices {
            shadow_instances[shadow_index].color[3] = 0.0;
            hidden_shadow_lanes += 1;
        }
    }
    println!("material workbench initial alpha: selected={} hidden-instance-lanes={} hidden-glyph-lanes={} hidden-shadow-lanes={}",
             plan.views[plan.selected_index].destination_id, hidden_instance_lanes, hidden_glyph_lanes, hidden_shadow_lanes);
}

fn compiler_overlay_state_plan(
    scene: &Scene,
    state_slot_ids: &[String],
    action_slot_ids: &[String],
    action_tile_masks: &HashMap<String, u64>,
    packet_worklists: &[CompiledPacketWorklist],
    instances: &[QuadInstance],
    placements: &[GlyphPlacementInstance],
) -> Result<Option<CompiledOverlayStatePlan>> {
    let Some(plan) = &scene.overlay_state_plan else {
        anyhow::ensure!(!scene.overlay_state_required,
                        "desktop-wide Scene marked overlay_state_required may not disable overlay_state_plan v1");
        println!("compiler overlay state: disabled entries=0");
        return Ok(None);
    };
    anyhow::ensure!(plan.abi_schema == OVERLAY_STATE_PLAN_ABI_SCHEMA && plan.abi_revision == OVERLAY_STATE_PLAN_ABI_REVISION,
                    "overlay state has unsupported ABI {}@{}", plan.abi_schema, plan.abi_revision);
    anyhow::ensure!(!plan.entries.is_empty(), "overlay state plan may not be empty");
    anyhow::ensure!(packet_worklists.get(RenderRequest::NO_PACKETS).map(|entry| entry.packet_indices.is_empty()).unwrap_or(false),
                    "overlay state requires compiler no-packets worklist");
    let mut seen_ids = HashSet::new();
    let mut compiled = Vec::with_capacity(plan.entries.len());
    for entry in &plan.entries {
        anyhow::ensure!(seen_ids.insert(entry.id.as_str()) && entry.initial_visible <= 1 && entry.initial_visible >= 0,
                        "overlay state {} has duplicate id or nonbinary initial visibility", entry.id);
        anyhow::ensure!(entry.state_index < state_slot_ids.len() && state_slot_ids[entry.state_index] == entry.state,
                        "overlay state {} has invalid state slot", entry.id);
        let state = scene.state_slots.get(entry.state_index)
            .with_context(|| format!("overlay state {} is absent", entry.id))?;
        anyhow::ensure!(state.initial == entry.initial_visible && state.id == entry.state,
                        "overlay state {} initial value disagrees with State Slot table", entry.id);
        anyhow::ensure!(!entry.close_actions.is_empty() && entry.close_actions.len() == entry.close_actions.iter().collect::<HashSet<_>>().len(),
                        "overlay state {} close action set must be nonempty and unique", entry.id);
        let mut transition_actions = vec![entry.open_action.clone()];
        transition_actions.extend(entry.close_actions.iter().cloned());
        for action_id in &transition_actions {
            let action_index = action_slot_ids.iter().position(|id| id == action_id)
                .with_context(|| format!("overlay state {} action {} lacks Action Slot", entry.id, action_id))?;
            let action = scene.actions.get(action_id)
                .with_context(|| format!("overlay state {} action {} is absent", entry.id, action_id))?;
            let expected = if action_id == &entry.open_action { 1 } else { 0 };
            anyhow::ensure!(action.action_index == action_index && action.writes.len() == 1
                            && action.writes[0].state == entry.state && action.writes[0].state_index == entry.state_index
                            && action.writes[0].op == "set" && action.writes[0].value == expected
                            && action.gpu_updates.is_empty() && action.instance_updates.is_empty(),
                            "overlay state {} action {} is not a closed literal visibility transition", entry.id, action_id);
        }
        anyhow::ensure!(entry.event_slots.len() >= transition_actions.len()
                        && entry.event_slots.windows(2).all(|pair| pair[0] < pair[1]),
                        "overlay state {} event slots must be fixed ascending addresses", entry.id);
        for &slot in &entry.event_slots {
            let event = scene.event_map.get(slot)
                .with_context(|| format!("overlay state {} event slot {} is absent", entry.id, slot))?;
            let action = event._action.as_ref().with_context(|| format!("overlay state {} event slot {} has no action", entry.id, slot))?;
            anyhow::ensure!(transition_actions.iter().any(|id| id == action),
                            "overlay state {} event slot {} has foreign action {}", entry.id, slot, action);
        }
        anyhow::ensure!(entry.instance_offsets.windows(2).all(|pair| pair[0] < pair[1])
                        && entry.instance_offsets.iter().all(|offset| offset % std::mem::size_of::<QuadInstance>() == 0 && offset / std::mem::size_of::<QuadInstance>() < instances.len()),
                        "overlay state {} has invalid quad alpha offsets", entry.id);
        anyhow::ensure!(entry.glyph_slots.windows(2).all(|pair| pair[0] < pair[1])
                        && entry.glyph_slots.iter().all(|slot| *slot < placements.len()),
                        "overlay state {} has invalid glyph alpha slots", entry.id);
        let shadow_plan = scene.shadow_surface_plan.as_ref().context("overlay state requires shadow surface plan")?;
        let shadow_indices = shadow_plan.layers.iter().enumerate()
            .filter_map(|(index, layer)| entry.instance_offsets.contains(&layer.source_instance_offset).then_some(index))
            .collect::<Vec<_>>();
        anyhow::ensure!(!shadow_indices.is_empty() && shadow_indices.windows(2).all(|pair| pair[0] < pair[1]),
                        "overlay state {} has no stable elevated shadow layers", entry.id);
        let tile_mask = tile_mask(&entry.tile_ids, scene.render_schedules[0].tiles.len(), &format!("overlay state {}", entry.id))?;
        anyhow::ensure!(tile_mask != 0 && transition_actions.iter().all(|action| action_tile_masks.get(action).copied() == Some(tile_mask)),
                        "overlay state {} action tile scope disagrees with fixed overlay tiles", entry.id);
        let instance_alphas = entry.instance_offsets.iter().map(|offset| instances[offset / std::mem::size_of::<QuadInstance>()].color[3]).collect();
        compiled.push(CompiledOverlayStateEntry {
            id: entry.id.clone(), state_index: entry.state_index, open_action: entry.open_action.clone(), close_actions: entry.close_actions.clone(),
            event_slots: entry.event_slots.clone(), instance_offsets: entry.instance_offsets.clone(), instance_alphas,
            glyph_slots: entry.glyph_slots.clone(), shadow_indices, tile_mask,
        });
    }
    println!("compiler overlay state: v1 entries={} fixed-alpha-lanes={} no-packets", compiled.len(),
             compiled.iter().map(|entry| entry.instance_offsets.len() + entry.glyph_slots.len()).sum::<usize>());
    Ok(Some(CompiledOverlayStatePlan { entries: compiled }))
}

fn compiler_modal_focus_subgraph_plan(
    scene: &Scene,
    state_slot_ids: &[String],
    overlay_state_plan: &Option<CompiledOverlayStatePlan>,
    event_tile_masks: &[EventTileMasks],
) -> Result<Option<CompiledModalFocusSubgraphPlan>> {
    let Some(plan) = &scene.modal_focus_subgraph_plan else {
        anyhow::ensure!(!scene.modal_focus_subgraph_required,
                        "Scene marked modal_focus_subgraph_required may not disable modal_focus_subgraph_plan v1");
        println!("compiler modal focus: disabled entries=0");
        return Ok(None);
    };
    anyhow::ensure!(plan.abi_schema == MODAL_FOCUS_SUBGRAPH_ABI_SCHEMA && plan.abi_revision == MODAL_FOCUS_SUBGRAPH_ABI_REVISION,
                    "modal focus has unsupported ABI {}@{}", plan.abi_schema, plan.abi_revision);
    let overlay_plan = overlay_state_plan.as_ref().context("modal focus requires an admitted overlay_state_plan")?;
    anyhow::ensure!(!plan.entries.is_empty(), "modal focus plan may not be empty");
    let mut seen_ids = HashSet::new();
    let mut compiled = Vec::with_capacity(plan.entries.len());
    for entry in &plan.entries {
        anyhow::ensure!(seen_ids.insert(entry.id.as_str()), "modal focus has duplicate overlay id {}", entry.id);
        anyhow::ensure!(entry.state_index < state_slot_ids.len() && state_slot_ids[entry.state_index] == entry.state,
                        "modal focus {} has invalid state slot", entry.id);
        let overlay = overlay_plan.entries.iter().find(|candidate| candidate.id == entry.id)
            .with_context(|| format!("modal focus {} lacks admitted overlay state entry", entry.id))?;
        anyhow::ensure!(overlay.state_index == entry.state_index,
                        "modal focus {} state slot disagrees with overlay state plan", entry.id);
        let restore_event = scene.event_map.get(entry.restore_event_slot)
            .with_context(|| format!("modal focus {} restore event slot is absent", entry.id))?;
        anyhow::ensure!(restore_event._action.as_deref() == Some(overlay.open_action.as_str())
                        && overlay.event_slots.contains(&entry.restore_event_slot),
                        "modal focus {} restore event is not the unique admitted open action", entry.id);
        let count = entry.focus_event_slots.len();
        anyhow::ensure!((2..=6).contains(&count)
                        && entry.next_slots.len() == count && entry.previous_slots.len() == count
                        && entry.focus_event_slots.iter().collect::<HashSet<_>>().len() == count,
                        "modal focus {} must have a unique 2..6 event Tab ring", entry.id);
        let mut expected_allowed = overlay.event_slots.iter().copied()
            .filter(|slot| scene.event_map.get(*slot).and_then(|event| event._action.as_ref())
                    .is_some_and(|action| overlay.close_actions.contains(action)))
            .collect::<Vec<_>>();
        expected_allowed.sort_unstable();
        for (index, &slot) in entry.focus_event_slots.iter().enumerate() {
            let event = scene.event_map.get(slot)
                .with_context(|| format!("modal focus {} target slot {} is absent", entry.id, slot))?;
            anyhow::ensure!(overlay.event_slots.contains(&slot)
                            && event._action.as_ref().is_some_and(|action| overlay.close_actions.contains(action)),
                            "modal focus {} target slot {} escapes the overlay close-event set", entry.id, slot);
            anyhow::ensure!(entry.next_slots[index] == entry.focus_event_slots[(index + 1) % count]
                            && entry.previous_slots[index] == entry.focus_event_slots[(index + count - 1) % count],
                            "modal focus {} target slot {} has a noncanonical Tab ring edge", entry.id, slot);
            let masks = event_tile_masks.get(slot).with_context(|| format!("modal focus {} target slot {} lacks tile mask", entry.id, slot))?;
            anyhow::ensure!(masks.release == overlay.tile_mask,
                            "modal focus {} target slot {} widened local tile scope", entry.id, slot);
        }
        anyhow::ensure!(entry.allowed_event_slots == expected_allowed,
                        "modal focus {} allowed event set must equal its fixed Tab targets", entry.id);
        let tile_mask = tile_mask(&entry.tile_ids, scene.render_schedules[0].tiles.len(), &format!("modal focus {}", entry.id))?;
        anyhow::ensure!(tile_mask == overlay.tile_mask,
                        "modal focus {} tile mask disagrees with overlay state plan", entry.id);
        compiled.push(CompiledModalFocusSubgraphEntry {
            id: entry.id.clone(), state_index: entry.state_index, restore_event_slot: entry.restore_event_slot,
            focus_event_slots: entry.focus_event_slots.clone(), next_slots: entry.next_slots.clone(),
            previous_slots: entry.previous_slots.clone(), allowed_event_slots: entry.allowed_event_slots.clone(),
            tile_mask, current_index: 0,
        });
    }
    println!("compiler modal focus: v1 entries={} fixed-tab-targets={} background-isolated no-packets",
             compiled.len(), compiled.iter().map(|entry| entry.focus_event_slots.len()).sum::<usize>());
    Ok(Some(CompiledModalFocusSubgraphPlan { entries: compiled }))
}

fn compiler_modal_focus_visual_plan(
    scene: &Scene,
    overlay_state_plan: &Option<CompiledOverlayStatePlan>,
    modal_focus_subgraph_plan: &Option<CompiledModalFocusSubgraphPlan>,
    event_tile_masks: &[EventTileMasks],
    instances: &[QuadInstance],
) -> Result<Option<CompiledModalFocusVisualPlan>> {
    let Some(plan) = &scene.modal_focus_visual_plan else {
        anyhow::ensure!(!scene.modal_focus_visual_required,
                        "Scene marked modal_focus_visual_required may not disable modal_focus_visual_plan v1");
        println!("compiler modal focus visual: disabled entries=0");
        return Ok(None);
    };
    anyhow::ensure!(plan.abi_schema == MODAL_FOCUS_VISUAL_PLAN_ABI_SCHEMA && plan.abi_revision == MODAL_FOCUS_VISUAL_PLAN_ABI_REVISION,
                    "modal focus visual has unsupported ABI {}@{}", plan.abi_schema, plan.abi_revision);
    let overlay_plan = overlay_state_plan.as_ref().context("modal focus visual requires an admitted overlay_state_plan")?;
    let modal_plan = modal_focus_subgraph_plan.as_ref().context("modal focus visual requires an admitted modal_focus_subgraph_plan")?;
    anyhow::ensure!(!plan.entries.is_empty(), "modal focus visual plan may not be empty");
    let expected_count = modal_plan.entries.iter().map(|entry| entry.focus_event_slots.len()).sum::<usize>();
    anyhow::ensure!(plan.entries.len() == expected_count,
                    "modal focus visual entry count {} disagrees with fixed Tab target count {}", plan.entries.len(), expected_count);
    let mut seen_ids = HashSet::new();
    let mut ring_for_event_slot = vec![None; scene.event_map.len()];
    let mut compiled = Vec::with_capacity(plan.entries.len());
    for entry in &plan.entries {
        anyhow::ensure!(seen_ids.insert(entry.id.as_str()), "modal focus visual has duplicate ring id {}", entry.id);
        let event = scene.event_map.get(entry.focus_event_slot)
            .with_context(|| format!("modal focus visual {} references absent event slot {}", entry.id, entry.focus_event_slot))?;
        anyhow::ensure!(event.slot == entry.focus_event_slot,
                        "modal focus visual {} event slot is not its canonical Event Map address", entry.id);
        anyhow::ensure!(entry.source_instance_offset > 0
                        && entry.source_instance_offset % std::mem::size_of::<QuadInstance>() == 0
                        && entry.source_instance_offset / std::mem::size_of::<QuadInstance>() < instances.len()
                        && entry.source_instance_offset == event.instance_offset,
                        "modal focus visual {} has invalid source instance offset", entry.id);
        anyhow::ensure!(entry.id == format!("{}$focus-ring", event.node),
                        "modal focus visual {} is not canonically named for Event Map target {}", entry.id, event.node);
        anyhow::ensure!(entry.x.is_finite() && entry.y.is_finite() && entry.width.is_finite() && entry.height.is_finite()
                        && entry.radius_px.is_finite() && entry.thickness_px.is_finite()
                        && entry.width > 0.0 && entry.height > 0.0 && entry.radius_px > 0.0 && entry.thickness_px > 0.0
                        && entry.radius_px <= entry.width.min(entry.height) * 0.5,
                        "modal focus visual {} has non-finite or invalid ring geometry", entry.id);
        let expected_x = event.x - FOCUS_RING_HALO_PX;
        let expected_y = event.y - FOCUS_RING_HALO_PX;
        let expected_width = event.width + FOCUS_RING_HALO_PX * 2.0;
        let expected_height = event.height + FOCUS_RING_HALO_PX * 2.0;
        let expected_radius = 12.0f32.min(expected_width.min(expected_height) * 0.5);
        anyhow::ensure!((entry.x - expected_x).abs() <= 1e-4
                        && (entry.y - expected_y).abs() <= 1e-4
                        && (entry.width - expected_width).abs() <= 1e-4
                        && (entry.height - expected_height).abs() <= 1e-4
                        && (entry.radius_px - expected_radius).abs() <= 1e-4
                        && (entry.thickness_px - FOCUS_RING_THICKNESS_PX).abs() <= 1e-4
                        && entry.color.iter().zip(FOCUS_RING_COLOR).all(|(actual, expected)| (*actual - expected).abs() <= 1e-6),
                        "modal focus visual {} violates the fixed halo/outline/color recipe", entry.id);
        let modal_entry_index = modal_plan.entries.iter().position(|modal| modal.focus_event_slots.contains(&entry.focus_event_slot))
            .with_context(|| format!("modal focus visual {} target slot {} is outside the admitted Tab subgraph", entry.id, entry.focus_event_slot))?;
        let modal = &modal_plan.entries[modal_entry_index];
        let overlay = overlay_plan.entries.iter().find(|candidate| candidate.id == modal.id)
            .with_context(|| format!("modal focus visual {} lacks paired overlay entry {}", entry.id, modal.id))?;
        let tile_mask = tile_mask(&entry.tile_ids, scene.render_schedules[0].tiles.len(), &format!("modal focus visual {}", entry.id))?;
        let event_mask = event_tile_masks.get(entry.focus_event_slot)
            .with_context(|| format!("modal focus visual {} target slot lacks an event tile mask", entry.id))?;
        anyhow::ensure!(tile_mask != 0 && tile_mask == modal.tile_mask && tile_mask == overlay.tile_mask && event_mask.release == tile_mask,
                        "modal focus visual {} widened or mismatched its fixed local tile scope", entry.id);
        anyhow::ensure!(ring_for_event_slot[entry.focus_event_slot].replace(compiled.len()).is_none(),
                        "modal focus visual has multiple rings for Event Map slot {}", entry.focus_event_slot);
        compiled.push(CompiledModalFocusVisualEntry {
            id: entry.id.clone(), modal_entry_index, focus_event_slot: entry.focus_event_slot,
            source_instance_offset: entry.source_instance_offset, x: entry.x, y: entry.y,
            width: entry.width, height: entry.height, radius_px: entry.radius_px,
            thickness_px: entry.thickness_px, color: entry.color, tile_mask,
        });
    }
    for modal in &modal_plan.entries {
        for &slot in &modal.focus_event_slots {
            anyhow::ensure!(ring_for_event_slot.get(slot).and_then(|ring| *ring).is_some(),
                            "modal focus visual plan lacks a ring for fixed Tab target slot {}", slot);
        }
    }
    println!("compiler modal focus visual: v1 entries={} preallocated-outline-quads={} halo={}px thickness={}px no-runtime-geometry",
             compiled.len(), compiled.len(), FOCUS_RING_HALO_PX, FOCUS_RING_THICKNESS_PX);
    Ok(Some(CompiledModalFocusVisualPlan { entries: compiled, ring_for_event_slot }))
}

fn make_focus_ring_gpu_instances(
    plan: &Option<CompiledModalFocusVisualPlan>,
    canvas: VerifiedVisualCanvas,
) -> (Vec<QuadInstance>, Vec<GpuFocusRingMeta>) {
    let Some(plan) = plan else { return (Vec::new(), Vec::new()); };
    let canvas_width = canvas.width as f32;
    let canvas_height = canvas.height as f32;
    let mut instances = Vec::with_capacity(plan.entries.len());
    let mut metadata = Vec::with_capacity(plan.entries.len());
    for entry in &plan.entries {
        let ndc_pos = [2.0 * entry.x / canvas_width - 1.0,
                       1.0 - 2.0 * (entry.y + entry.height) / canvas_height];
        let ndc_size = [2.0 * entry.width / canvas_width,
                        2.0 * entry.height / canvas_height];
        instances.push(QuadInstance {
            pos: ndc_pos,
            size: ndc_size,
            color: [entry.color[0], entry.color[1], entry.color[2], 0.0],
            glyph_word_offset: 0,
            glyph_enabled: 0,
            glyph_count: 0,
        });
        metadata.push(GpuFocusRingMeta {
            radius_px: entry.radius_px,
            thickness_px: entry.thickness_px,
            width_px: entry.width,
            height_px: entry.height,
        });
    }
    println!("compiler modal focus GPU resources: ring-quads={} metadata={} alpha-initial=0", instances.len(), metadata.len());
    (instances, metadata)
}

fn compiler_release_motion_tracks(scene: &Scene, event_tile_masks: &[EventTileMasks]) -> Result<Vec<CompiledReleaseTrack>> {
    anyhow::ensure!(scene.animation_tracks.len() == scene.event_map.len(),
                    "release motion track count {} disagrees with event map {}", scene.animation_tracks.len(), scene.event_map.len());
    let mut seen_ids = HashSet::new();
    let mut seen_slots = HashSet::new();
    let mut compiled = Vec::with_capacity(scene.animation_tracks.len());
    for track in &scene.animation_tracks {
        let event_slot = scene.event_map.iter().position(|event| event.node == track.node)
            .with_context(|| format!("release motion {} references unknown event {}", track.id, track.node))?;
        let event = &scene.event_map[event_slot];
        anyhow::ensure!(track.id == format!("release-{}", event.node)
                        && seen_ids.insert(track.id.as_str()) && seen_slots.insert(event_slot),
                        "release motion track {} is not a unique canonical event release", track.id);
        anyhow::ensure!(track.instance_offset == event.instance_offset
                        && track.pos_offset == event.instance_offset
                        && track.color_offset == event.instance_offset + 16
                        && track.instance_offset % std::mem::size_of::<QuadInstance>() == 0
                        && track.instance_offset / std::mem::size_of::<QuadInstance>() < scene.resource_budget.instance_capacity,
                        "release motion {} offsets escape the fixed event instance", track.id);
        anyhow::ensure!(track.duration_ms == 80 && track.easing == "ease-out",
                        "release motion {} must use the canonical finite 80ms ease-out recipe", track.id);
        anyhow::ensure!(track.pos_from == event.pressed_pos && track.pos_to == event.base_pos
                        && track.color_from == event.pressed_color && track.color_to == event.base_color,
                        "release motion {} endpoints disagree with compiler Event Map", track.id);
        anyhow::ensure!(track.pos_from.iter().chain(track.pos_to.iter()).chain(track.color_from.iter()).chain(track.color_to.iter()).all(|value| value.is_finite()),
                        "release motion {} contains a non-finite endpoint", track.id);
        anyhow::ensure!(track.damage.kind == "rect" && track.damage.node == event.node
                        && (track.damage.x - event.x).abs() < 0.001
                        && (track.damage.y - event.y).abs() < 0.001
                        && (track.damage.width - event.width).abs() < 0.001
                        && (track.damage.height - event.height).abs() < 0.001
                        && track.damage.instance_offset == event.instance_offset,
                        "release motion {} damage witness disagrees with fixed event geometry", track.id);
        let release_task = scene.frame_schedule.iter().find(|task| task.id == track.id)
            .with_context(|| format!("release motion {} has no compiler frame task", track.id))?;
        anyhow::ensure!(release_task.kind == "release"
                        && release_task.writes.len() == 2
                        && release_task.writes.iter().any(|write| write.offset == track.pos_offset && write.byte_length == 8)
                        && release_task.writes.iter().any(|write| write.offset == track.color_offset && write.byte_length == 16),
                        "release motion {} frame task does not own the fixed position/color fields", track.id);
        let tile_mask = event_tile_masks.get(event_slot).map(|masks| masks.release)
            .with_context(|| format!("release motion {} has no event tile mask", track.id))?;
        anyhow::ensure!(tile_mask != 0, "release motion {} has empty damage tile mask", track.id);
        compiled.push(CompiledReleaseTrack {
            id: track.id.clone(), event_slot, instance_offset: track.instance_offset,
            pos_offset: track.pos_offset, color_offset: track.color_offset, duration_ms: track.duration_ms,
            pos_from: track.pos_from, pos_to: track.pos_to, color_from: track.color_from, color_to: track.color_to,
            tile_mask,
        });
    }
    println!("compiler release motion: tracks={} recipe=80ms-ease-out fixed-fields=pos+color", compiled.len());
    Ok(compiled)
}

fn compiler_log_browser_plans(
    scene: &Scene,
    lists: &[CompiledVirtualListPlan],
    interactions: &[CompiledListInteractionPlan],
    packet_worklists: &[CompiledPacketWorklist],
) -> Result<Vec<CompiledLogBrowserPlan>> {
    let mut seen_ids = HashSet::new();
    let mut seen_lists = HashSet::new();
    let schedule = scene.render_schedules.first().context("log browser requires a compiler render schedule")?;
    let expected_names = ["INFO", "WARN", "ERROR", "DEBUG"];
    let mut compiled = Vec::with_capacity(scene.log_browser_plans.len());
    for artifact in &scene.log_browser_plans {
        anyhow::ensure!(artifact.abi_schema == LOG_BROWSER_PLAN_ABI_SCHEMA && artifact.abi_revision == LOG_BROWSER_PLAN_ABI_REVISION,
                        "log browser {} has unsupported ABI {}@{}", artifact.id, artifact.abi_schema, artifact.abi_revision);
        anyhow::ensure!(seen_ids.insert(artifact.id.as_str()) && seen_lists.insert(artifact.list_id.as_str()),
                        "log browser {} duplicates its ID or list binding", artifact.id);
        let list_index = lists.iter().position(|list| list.id == artifact.list_id)
            .with_context(|| format!("log browser {} refers to unknown virtual list {}", artifact.id, artifact.list_id))?;
        let list = &lists[list_index];
        let table = list.data_register_table.as_ref().context("log browser requires compact data-register table")?;
        anyhow::ensure!(artifact.packet_worklist_index == RenderRequest::NO_PACKETS
                        && packet_worklists.get(artifact.packet_worklist_index).map(|worklist| worklist.packet_indices.is_empty()).unwrap_or(false),
                        "log browser {} widened packet worklist", artifact.id);
        let update_indices = artifact.append_updates.iter().map(|update| update.index).collect::<Vec<_>>();
        anyhow::ensure!(!update_indices.is_empty() && update_indices == artifact.append_indices
                        && update_indices.windows(2).all(|pair| pair[0] + 1 == pair[1])
                        && *update_indices.last().unwrap() + 1 == list.logical_capacity,
                        "log browser {} append batch is not a contiguous logical tail", artifact.id);
        anyhow::ensure!(artifact.append_batch_id == format!("{}-append", artifact.id),
                        "log browser {} append batch ID is not canonical", artifact.id);
        for update in &artifact.append_updates {
            anyhow::ensure!(update.index < list.logical_capacity,
                            "log browser {} append update escapes fixed logical capacity", artifact.id);
            compact_register_glyphs(&update.value, table.register_width, table.atlas_page)
                .with_context(|| format!("log browser {} append update escapes fixed legacy glyph domain/width", artifact.id))?;
        }
        let detail_placements = scene.glyph_placement_plan.iter()
            .filter(|placement| placement.node == artifact.detail_node_id)
            .collect::<Vec<_>>();
        let placement_is_covered = |placement: &&GlyphPlacementEntry| artifact.detail_tile_ids.iter().any(|tile_id| schedule.tiles.get(*tile_id).map(|tile| tile.glyph_packet_ranges.iter().any(|range| (placement.slot as u32) >= range.first_placement && (placement.slot as u32) < range.first_placement + range.placement_count)).unwrap_or(false));
        let expected_offsets = detail_placements.iter().filter(|placement| placement_is_covered(placement)).map(|placement| placement.glyph_byte_offset).collect::<Vec<_>>();
        anyhow::ensure!(!expected_offsets.is_empty() && artifact.detail_glyph_offsets == expected_offsets
                        && artifact.detail_glyph_offsets.windows(2).all(|pair| pair[0] + GLYPH_CELL_BYTES == pair[1])
                        && artifact.detail_glyph_offsets.iter().all(|offset| offset % 4 == 0 && *offset + 4 <= scene.resource_budget.glyph_capacity * GLYPH_CELL_BYTES),
                        "log browser {} detail glyph range disagrees with compiler placement plan", artifact.id);
        anyhow::ensure!(!artifact.detail_tile_ids.is_empty() && artifact.detail_tile_ids.windows(2).all(|pair| pair[0] < pair[1])
                        && !expected_offsets.is_empty(),
                        "log browser {} detail tile scope is missing or widened", artifact.id);
        let detail_tile_mask = artifact.detail_tile_ids.iter().fold(0u64, |mask, tile_id| mask | (1u64 << tile_id));
        let interaction = interactions.get(list_index).context("log browser list has no interaction color table")?;
        anyhow::ensure!(artifact.row_color_offsets == interaction.row_color_offsets && artifact.row_color_offsets.len() == list.physical_slots,
                        "log browser {} row color addresses disagree with frozen list interaction plan", artifact.id);
        anyhow::ensure!(artifact.levels.len() == expected_names.len()
                        && artifact.levels.iter().zip(expected_names).all(|(level, name)| level.name == name && level.color.iter().all(|component| component.is_finite() && *component >= 0.0 && *component <= 1.0)),
                        "log browser {} level palette is not canonical", artifact.id);
        let level_colors = [artifact.levels[0].color, artifact.levels[1].color, artifact.levels[2].color, artifact.levels[3].color];
        println!("compiler log browser: id={} list={} append={} records={} detail={} glyph-cells={} tiles={:?} worklist={}",
                 artifact.id, artifact.list_id, artifact.append_batch_id, artifact.append_updates.len(), artifact.detail_node_id,
                 artifact.detail_glyph_offsets.len(), artifact.detail_tile_ids, artifact.packet_worklist_index);
        compiled.push(CompiledLogBrowserPlan {
            id: artifact.id.clone(), list_index, append_batch_id: artifact.append_batch_id.clone(),
            append_updates: artifact.append_updates.clone(), detail_glyph_offsets: artifact.detail_glyph_offsets.clone(),
            detail_tile_mask, row_color_offsets: artifact.row_color_offsets.clone(), level_colors,
            packet_worklist_index: artifact.packet_worklist_index,
        });
    }
    Ok(compiled)
}

fn compiler_row_activation_plans(
    scene: &Scene,
    lists: &[CompiledVirtualListPlan],
    action_slot_ids: &[String],
    action_tile_masks: &HashMap<String, u64>,
    batches: &HashMap<String, CompiledBatch>,
    packet_worklists: &[CompiledPacketWorklist],
) -> Result<Vec<CompiledRowActivationPlan>> {
    let mut seen_lists = HashSet::new();
    let mut compiled = Vec::with_capacity(scene.row_activation_plans.len());
    for artifact in &scene.row_activation_plans {
        anyhow::ensure!(artifact.abi_schema == ROW_ACTIVATION_PLAN_ABI_SCHEMA && artifact.abi_revision == ROW_ACTIVATION_PLAN_ABI_REVISION,
                        "row activation {} has unsupported ABI {}@{}", artifact.list_id, artifact.abi_schema, artifact.abi_revision);
        anyhow::ensure!(seen_lists.insert(artifact.list_id.as_str()),
                        "row activation plan duplicates list {}", artifact.list_id);
        let list_index = lists.iter().position(|list| list.id == artifact.list_id)
            .with_context(|| format!("row activation {} refers to unknown virtual list", artifact.list_id))?;
        anyhow::ensure!(artifact.physical_slot_rule == "logical-mod-physical-slots",
                        "row activation {} uses unsupported physical slot rule", artifact.list_id);
        let slot_id = action_slot_ids.get(artifact.action_slot_index)
            .with_context(|| format!("row activation {} action slot outside canonical table", artifact.list_id))?;
        anyhow::ensure!(slot_id == &artifact.action_id,
                        "row activation {} action ID/slot mismatch", artifact.list_id);
        let expected_tiles = *action_tile_masks.get(&artifact.action_id)
            .with_context(|| format!("row activation {} action {} has no compiler tile mask", artifact.list_id, artifact.action_id))?;
        anyhow::ensure!(artifact.tile_mask == expected_tiles,
                        "row activation {} tile mask widened or disagrees with Action Plan", artifact.list_id);
        anyhow::ensure!(artifact.strategy_id == "coalesced",
                        "row activation {} must use compiler coalesced strategy", artifact.list_id);
        let batch = batches.get(&artifact.activate_batch_id)
            .with_context(|| format!("row activation {} missing activate batch {}", artifact.list_id, artifact.activate_batch_id))?;
        anyhow::ensure!(batch.strategy == CompilerStrategy::Coalesced && batch.execution_refs.iter().any(|reference| matches!(reference, CompiledTaskRef::Action(index) if *index == artifact.action_slot_index)),
                        "row activation {} batch does not execute its fixed Action Slot", artifact.list_id);
        anyhow::ensure!((batch.tile_mask & artifact.tile_mask) == artifact.tile_mask,
                        "row activation {} activate batch omits Action Plan tile mask", artifact.list_id);
        anyhow::ensure!(batch.composite_worklist_index == artifact.packet_worklist_index && artifact.packet_worklist_index == RenderRequest::NO_PACKETS,
                        "row activation {} widened packet worklist", artifact.list_id);
        anyhow::ensure!(packet_worklists.get(artifact.packet_worklist_index).map(|worklist| worklist.packet_indices.is_empty()).unwrap_or(false),
                        "row activation {} no-packets worklist must be empty", artifact.list_id);
        println!("compiler row activation: list={} action={} slot={} batch={} tile-mask=0x{:016x} worklist={}",
                 artifact.list_id, artifact.action_id, artifact.action_slot_index, artifact.activate_batch_id, artifact.tile_mask, artifact.packet_worklist_index);
        compiled.push(CompiledRowActivationPlan {
            list_index,
            action_slot_index: artifact.action_slot_index,
            activate_batch_id: artifact.activate_batch_id.clone(),
            tile_mask: artifact.tile_mask,
            packet_worklist_index: artifact.packet_worklist_index,
        });
    }
    Ok(compiled)
}

fn compiler_state_slots(scene: &Scene) -> Result<(Vec<String>, Vec<i64>)> {
    anyhow::ensure!(scene.state_slots.len() == scene.state.len(),
                    "State Slot table must exactly cover compiler debug state table");
    let mut ids = Vec::with_capacity(scene.state_slots.len());
    let mut values = Vec::with_capacity(scene.state_slots.len());
    let mut previous_id: Option<&str> = None;
    for (expected_index, slot) in scene.state_slots.iter().enumerate() {
        anyhow::ensure!(slot.index == expected_index, "State Slot table must use dense canonical indices");
        if let Some(previous) = previous_id {
            anyhow::ensure!(previous < slot.id.as_str(), "State Slot IDs must be strict lexical order");
        }
        anyhow::ensure!(scene.state.get(&slot.id) == Some(&slot.initial),
                        "State Slot {} disagrees with compiler debug state initial value", slot.id);
        previous_id = Some(&slot.id);
        ids.push(slot.id.clone());
        values.push(slot.initial);
    }
    println!("compiler state slots: {} fixed value address(es), lexical ABI", ids.len());
    Ok((ids, values))
}

fn assert_state_slot(state_slot_ids: &[String], state_index: usize, state: &str, owner: &str) -> Result<()> {
    let slot_id = state_slot_ids.get(state_index)
        .with_context(|| format!("{owner}: state_index {state_index} outside compiler State Slot table"))?;
    anyhow::ensure!(slot_id == state, "{owner}: state symbol {state} disagrees with compiler state_slot[{state_index}]={slot_id}");
    Ok(())
}

fn compiler_action_slots(scene: &Scene) -> Result<(Vec<String>, Vec<ActionPlan>)> {
    anyhow::ensure!(scene.action_slots.len() == scene.actions.len(),
                    "Action Slot table must exactly cover compiler audit action map");
    let mut ids = Vec::with_capacity(scene.action_slots.len());
    let mut plans = Vec::with_capacity(scene.action_slots.len());
    let mut previous_id: Option<&str> = None;
    for (expected_index, slot) in scene.action_slots.iter().enumerate() {
        anyhow::ensure!(slot.index == expected_index, "Action Slot table must use dense canonical indices");
        if let Some(previous) = previous_id {
            anyhow::ensure!(previous < slot.id.as_str(), "Action Slot IDs must be strict lexical order");
        }
        let plan = scene.actions.get(&slot.id)
            .with_context(|| format!("Action Slot {} absent from compiler audit action map", slot.id))?;
        anyhow::ensure!(plan.action_index == expected_index,
                        "Action Slot {} disagrees with action plan action_index", slot.id);
        previous_id = Some(&slot.id);
        ids.push(slot.id.clone());
        plans.push(plan.clone());
    }
    for event in &scene.event_map {
        match (&event._action, event.action_index, event.transaction_op.as_deref(), event.transaction_index) {
            (Some(action), Some(action_index), None, None) => {
                let action_id = ids.get(action_index)
                    .with_context(|| format!("Event {} action_index outside Action Slot table", event.node))?;
                anyhow::ensure!(action_id == action, "Event {} action/id index mismatch", event.node);
            }
            (None, None, Some(operation @ ("commit" | "reset")), Some(transaction_index)) => {
                let transaction = scene.transactions.get(transaction_index)
                    .with_context(|| format!("Event {} transaction_index outside compiler table", event.node))?;
                anyhow::ensure!(transaction.index == transaction_index,
                                "Event {} transaction table index mismatch", event.node);
                println!("compiler transaction button: node={} operation={} transaction={} index={}",
                         event.node, operation, transaction.id, transaction_index);
            }
            _ => anyhow::bail!("Event {} must carry exactly one compiler action or transaction dispatch", event.node),
        }
    }
    println!("compiler action slots: {} fixed action address(es), lexical ABI", ids.len());
    Ok((ids, plans))
}

fn compiler_action_state_slots(scene: &Scene, state_slot_ids: &[String]) -> Result<()> {
    for (action_id, action) in &scene.actions {
        for write in &action.writes {
            assert_state_slot(state_slot_ids, write.state_index, &write.state, &format!("action {action_id} state write"))?;
            anyhow::ensure!(matches!(write.op.as_str(), "add" | "set"),
                            "action {action_id} has unsupported state operation {}", write.op);
        }
        for update in &action.gpu_updates {
            assert_state_slot(state_slot_ids, update.state_index, &update.state, &format!("action {action_id} glyph patch"))?;
            anyhow::ensure!(update.kind == "text-run", "action {action_id} has unsupported GPU update kind {}", update.kind);
        }
        for update in &action.instance_updates {
            assert_state_slot(state_slot_ids, update.state_index, &update.state, &format!("action {action_id} instance patch"))?;
        }
    }
    Ok(())
}

fn compiler_focus_graph(scene: &Scene) -> Result<Option<CompiledFocusGraph>> {
    if scene.focus_graph.entries.is_empty() {
        anyhow::ensure!(scene.focus_graph.initial_slot == -1, "empty compiler Focus Graph must use initial_slot=-1");
        return Ok(None);
    }
    let schedule = scene.render_schedules.first().context("focus graph requires a compiler render schedule")?;
    let tile_count = schedule.tiles.len();
    let count = scene.focus_graph.entries.len();
    anyhow::ensure!(scene.focus_graph.initial_slot >= 0 && (scene.focus_graph.initial_slot as usize) < count,
                    "compiler Focus Graph initial_slot is outside the fixed entry table");
    let mut compiled = Vec::with_capacity(count);
    let mut prior_tab = None;
    for (expected_slot, entry) in scene.focus_graph.entries.iter().enumerate() {
        anyhow::ensure!(entry.slot == expected_slot, "focus entry {} must use dense stable slot {}", entry.node, expected_slot);
        if let Some(previous) = prior_tab {
            anyhow::ensure!(previous < entry.tab_index, "focus entries must be strictly ordered by compiler tab_index");
        }
        prior_tab = Some(entry.tab_index);
        anyhow::ensure!(entry.next_slot == (expected_slot + 1) % count,
                        "focus entry {} has non-canonical next_slot", entry.node);
        anyhow::ensure!(entry.previous_slot == (expected_slot + count - 1) % count,
                        "focus entry {} has non-canonical previous_slot", entry.node);
        assert_state_slot(&scene.state_slots.iter().map(|slot| slot.id.clone()).collect::<Vec<_>>(),
                          entry.state_index, &entry.state, &format!("focus entry {}", entry.node))?;
        let layout = scene.layout_plan.iter().find(|layout| layout.id == entry.node)
            .with_context(|| format!("focus entry {} has no Layout Plan entry", entry.node))?;
        anyhow::ensure!(layout._instance_offset == entry.instance_offset,
                        "focus entry {} instance_offset disagrees with Layout Plan", entry.node);
        anyhow::ensure!(layout.glyph_count > 0, "focus entry {} must own fixed text glyph slots", entry.node);
        let mask = tile_mask(&entry.tile_ids, tile_count, &format!("focus entry {}", entry.node))?;
        compiled.push(CompiledFocusEntry { node: entry.node.clone(), next_slot: entry.next_slot,
                                            previous_slot: entry.previous_slot, tile_mask: mask });
    }
    Ok(Some(CompiledFocusGraph { entries: compiled, current_slot: scene.focus_graph.initial_slot as usize }))
}

fn keyboard_key_index(key: &Key, ascii_upper: bool) -> Option<usize> {
    if ascii_upper {
        match key {
            Key::Character(text) if text.len() == 1 => {
                let byte = text.as_bytes()[0].to_ascii_uppercase();
                if byte.is_ascii_uppercase() { Some(usize::from(byte - b'A')) }
                else if byte == b' ' { Some(26) } else { None }
            }
            Key::Named(NamedKey::Space) => Some(26),
            Key::Named(NamedKey::Backspace) => Some(27),
            _ => None,
        }
    } else {
        match key {
            Key::Character(text) if text.len() == 1 => text.as_bytes()[0].checked_sub(b'0')
                .filter(|digit| *digit < 10).map(|digit| digit as usize),
            Key::Named(NamedKey::Backspace) => Some(10),
            _ => None,
        }
    }
}

fn compiler_keyboard_map(scene: &Scene, focus: Option<&CompiledFocusGraph>) -> Result<Option<CompiledKeyboardMap>> {
    if scene.keyboard_map.fields.is_empty() && scene.keyboard_map.transitions.is_empty() { return Ok(None); }
    let graph = focus.context("Keyboard Map requires a verified compiler Focus Graph")?;
    let schedule = scene.render_schedules.first().context("Keyboard Map requires a compiler render schedule")?;
    anyhow::ensure!(scene.keyboard_map.fields.len() == graph.entries.len(),
                    "Keyboard Map field count must equal fixed Focus Graph field count");
    let expected_transition_count: usize = scene.keyboard_map.fields.iter().map(|field| match field.charset.as_str() {
        "digits" => 11,
        "ascii-upper" => 28,
        _ => 0,
    }).sum();
    anyhow::ensure!(scene.keyboard_map.transitions.len() == expected_transition_count,
                    "Keyboard Map transition count disagrees with compiler charset table widths");
    let mut fields = Vec::with_capacity(graph.entries.len());
    let mut tables = Vec::with_capacity(graph.entries.len());
    for slot in 0..graph.entries.len() {
        let field = scene.keyboard_map.fields.iter().find(|field| field.focus_slot == slot)
            .with_context(|| format!("Keyboard Map lacks field for focus slot {slot}"))?;
        anyhow::ensure!(field.node == graph.entries[slot].node, "Keyboard field slot {slot} node disagrees with Focus Graph");
        anyhow::ensure!(field.state == scene.focus_graph.entries[slot].state &&
                        field.state_index == scene.focus_graph.entries[slot].state_index,
                        "Keyboard field {} state/index disagrees with Focus Graph", field.node);
        assert_state_slot(&scene.state_slots.iter().map(|slot| slot.id.clone()).collect::<Vec<_>>(),
                          field.state_index, &field.state, &format!("keyboard field {}", field.node))?;
        anyhow::ensure!(field.max_chars > 0 && field.glyph_id_offsets.len() == field.max_chars,
                        "Keyboard field {} must have one fixed glyph offset per character", field.node);
        if field.charset == "ascii-upper" {
            let register = field.ascii_text_register.as_ref().context("ascii-upper field lacks ascii_text_register")?;
            anyhow::ensure!(field.digit_register.is_none() && register.charset == "ascii-upper"
                            && register.max_chars == field.max_chars && register.atlas_page == 1,
                            "Keyboard field {} has non-canonical ASCII Text Register descriptor", field.node);
            let expected_mask = graph.entries[slot].tile_mask;
            anyhow::ensure!(tile_mask(&field.tile_ids, schedule.tiles.len(), &format!("keyboard field {}", field.node))? == expected_mask,
                            "Keyboard field {} tile mask disagrees with Focus Graph", field.node);
            anyhow::ensure!(field.glyph_id_offsets.len() == field.max_chars,
                            "ASCII field {} must have one fixed glyph offset per character", field.node);
            let mut table: Vec<Option<CompiledKeyboardTransition>> = vec![None; 28];
            for transition in scene.keyboard_map.transitions.iter().filter(|transition| transition.focus_slot == slot) {
                let key_index = match transition.key.as_str() {
                    "backspace" => 27,
                    "space" => 26,
                    key if key.starts_with("letter-") && key.len() == 8 => {
                        let byte = key.as_bytes()[7];
                        anyhow::ensure!(byte.is_ascii_uppercase(), "ASCII transition key must be letter-A..letter-Z");
                        usize::from(byte - b'A')
                    }
                    _ => anyhow::bail!("ASCII Keyboard Map contains unsupported key {}", transition.key),
                };
                anyhow::ensure!(table[key_index].is_none(), "ASCII Keyboard Map duplicates slot {slot} key {}", transition.key);
                anyhow::ensure!(tile_mask(&transition.tile_ids, schedule.tiles.len(), &format!("keyboard transition {}", transition.key))? == expected_mask,
                                "ASCII transition tile mask disagrees with field {}", field.node);
                let (kind, op, operand, glyph_id) = if key_index == 27 {
                    (KeyboardKind::Backspace, DigitRegisterOp::DropChar, 0, 1u32 << 16)
                } else if key_index == 26 {
                    (KeyboardKind::Insert, DigitRegisterOp::AppendChar, u32::from(b' '), 1u32 << 16)
                } else {
                    (KeyboardKind::Insert, DigitRegisterOp::AppendChar, u32::from(b'A' + key_index as u8), (1u32 << 16) | (key_index as u32 + 1))
                };
                let expected_op = match op { DigitRegisterOp::AppendChar => "append-char", DigitRegisterOp::DropChar => "drop-char", _ => unreachable!() };
                anyhow::ensure!(transition.kind == if kind == KeyboardKind::Insert { "insert" } else { "backspace" }
                                && transition.cursor_op == if kind == KeyboardKind::Insert { "advance" } else { "retreat" }
                                && transition.glyph_id == glyph_id && transition.register_op == expected_op
                                && transition.register_radix == 0 && transition.register_operand == operand,
                                "ASCII transition {} violates compiler fixed glyph/register ABI", transition.key);
                table[key_index] = Some(CompiledKeyboardTransition { kind, glyph_id, tile_mask: expected_mask,
                                                                       register_op: op, register_radix: 0, register_operand: operand });
            }
            let table = table.into_iter().collect::<Option<Vec<_>>>()
                .context("ASCII field lacks one or more A-Z/space/backspace transitions")?;
            println!("compiler ascii text register: slot={} field={} chars={} atlas_page=1 transitions=28", slot, field.node, register.max_chars);
            fields.push(CompiledKeyboardField { node: field.node.clone(), max_chars: field.max_chars, charset: field.charset.clone(),
                                                glyph_id_offsets: field.glyph_id_offsets.clone(), tile_mask: expected_mask,
                                                digit_register: None,
                                                ascii_text_register: Some(CompiledAsciiTextRegister { max_chars: register.max_chars,
                                                                                                       initial_packed: register.initial_packed,
                                                                                                       reset_packed: register.reset_packed,
                                                                                                       atlas_page: register.atlas_page }) });
            tables.push(table);
            continue;
        }
        anyhow::ensure!(field.charset == "digits", "Keyboard field {} has unsupported charset {}", field.node, field.charset);
        let register = field.digit_register.as_ref().context("digit field lacks digit_register")?;
        let expected_maximum = 10u32.checked_pow(field.max_chars as u32)
            .context("digit register width overflows u32")?.checked_sub(1)
            .context("digit register maximum underflows")?;
        anyhow::ensure!(register.radix == 10 && register.max_digits == field.max_chars,
                        "Keyboard field {} digit register radix/width disagrees with fixed decimal field", field.node);
        anyhow::ensure!(register.reset_value == 0 && register.maximum_value == expected_maximum,
                        "Keyboard field {} digit register reset/maximum is non-canonical", field.node);
        anyhow::ensure!(register.initial_value <= register.maximum_value,
                        "Keyboard field {} digit register initial value exceeds fixed capacity", field.node);
        let compiled_register = CompiledDigitRegister { radix: register.radix, max_digits: register.max_digits,
                                                        initial_value: register.initial_value, reset_value: register.reset_value,
                                                        maximum_value: register.maximum_value };
        let expected_mask = graph.entries[slot].tile_mask;
        anyhow::ensure!(tile_mask(&field.tile_ids, schedule.tiles.len(), &format!("keyboard field {}", field.node))? == expected_mask,
                        "Keyboard field {} tile mask disagrees with Focus Graph", field.node);
        let layout = scene.layout_plan.iter().find(|layout| layout.id == field.node)
            .with_context(|| format!("Keyboard field {} has no Layout Plan entry", field.node))?;
        anyhow::ensure!(layout.glyph_count == field.max_chars, "Keyboard field {} max_chars disagrees with Layout Plan", field.node);
        let mut previous = None;
        for &offset in &field.glyph_id_offsets {
            anyhow::ensure!(offset % 32 == 0, "Keyboard field {} glyph offset must be cell-aligned", field.node);
            if let Some(prior) = previous { anyhow::ensure!(prior < offset, "Keyboard field {} glyph offsets must be strictly increasing", field.node); }
            previous = Some(offset);
        }
        let mut table: Vec<Option<CompiledKeyboardTransition>> = vec![None; 11];
        for transition in scene.keyboard_map.transitions.iter().filter(|transition| transition.focus_slot == slot) {
            let key_index = match transition.key.as_str() {
                "backspace" => 10,
                key if key.starts_with("digit-") => key[6..].parse::<usize>().ok().filter(|digit| *digit < 10)
                    .context("Keyboard transition digit key must be digit-0..digit-9")?,
                _ => anyhow::bail!("Keyboard Map contains unsupported key {}", transition.key),
            };
            anyhow::ensure!(table[key_index].is_none(), "Keyboard Map duplicates slot {slot} key {}", transition.key);
            anyhow::ensure!(tile_mask(&transition.tile_ids, schedule.tiles.len(), &format!("keyboard transition {}", transition.key))? == expected_mask,
                            "Keyboard transition tile mask disagrees with field {}", field.node);
            let (kind, expected_cursor, expected_glyph) = if key_index == 10 {
                (KeyboardKind::Backspace, "retreat", 0)
            } else {
                (KeyboardKind::Insert, "advance", key_index as u32)
            };
            anyhow::ensure!(transition.kind == if kind == KeyboardKind::Insert { "insert" } else { "backspace" },
                            "Keyboard transition kind disagrees with fixed key semantics");
            anyhow::ensure!(transition.cursor_op == expected_cursor && transition.glyph_id == expected_glyph,
                            "Keyboard transition {} has non-canonical cursor/glyph plan", transition.key);
            let (register_op, expected_operand) = if key_index == 10 {
                (DigitRegisterOp::DropLast, 0)
            } else {
                (DigitRegisterOp::AppendDigit, key_index as u32)
            };
            let expected_register_op = match register_op {
                DigitRegisterOp::AppendDigit => "append-digit",
                DigitRegisterOp::DropLast => "drop-last",
                DigitRegisterOp::AppendChar | DigitRegisterOp::DropChar => unreachable!("ASCII ops are admitted by the ASCII branch"),
            };
            anyhow::ensure!(transition.register_op == expected_register_op && transition.register_radix == compiled_register.radix
                            && transition.register_operand == expected_operand,
                            "Keyboard transition {} has non-canonical Digit Register arithmetic", transition.key);
            table[key_index] = Some(CompiledKeyboardTransition { kind, glyph_id: transition.glyph_id, tile_mask: expected_mask,
                                                                   register_op, register_radix: transition.register_radix,
                                                                   register_operand: transition.register_operand });
        }
        let table = table.into_iter().collect::<Option<Vec<_>>>()
            .context("Keyboard Map field lacks one or more digit/Backspace transitions")?;
        println!("compiler digit register: slot={} field={} radix={} digits={} initial={} reset={} maximum={}",
                 slot, field.node, compiled_register.radix, compiled_register.max_digits,
                 compiled_register.initial_value, compiled_register.reset_value, compiled_register.maximum_value);
        fields.push(CompiledKeyboardField { node: field.node.clone(), max_chars: field.max_chars, charset: field.charset.clone(),
                                            glyph_id_offsets: field.glyph_id_offsets.clone(), tile_mask: expected_mask,
                                            digit_register: Some(compiled_register), ascii_text_register: None });
        tables.push(table);
    }
    Ok(Some(CompiledKeyboardMap { fields, transitions: tables }))
}

fn compiler_transactions(scene: &Scene, keyboard: Option<&CompiledKeyboardMap>) -> Result<Vec<CompiledTransactionPlan>> {
    if scene.transactions.is_empty() { return Ok(Vec::new()); }
    let keymap = keyboard.context("transaction table requires digit Keyboard Map")?;
    let tile_count = scene.render_schedules.first().context("transaction table requires render schedule")?.tiles.len();
    let mut expected_ids: Vec<String> = scene.transactions.iter().map(|plan| plan.id.clone()).collect();
    expected_ids.sort();
    for (index, plan) in scene.transactions.iter().enumerate() {
        anyhow::ensure!(plan.index == index && plan.id == expected_ids[index], "transaction table must be dense lexical order");
        anyhow::ensure!(plan.field_slots.len() > 1 && plan.field_slots.len() == plan.state_indices.len(),
                        "transaction {} must have two or more field/state slot pairs", plan.id);
        let mut fields = plan.field_slots.clone(); fields.sort(); fields.dedup();
        let mut states = plan.state_indices.clone(); states.sort(); states.dedup();
        anyhow::ensure!(fields.len() == plan.field_slots.len() && states.len() == plan.state_indices.len(),
                        "transaction {} repeats a field or state slot", plan.id);
        for (&field_slot, &state_index) in plan.field_slots.iter().zip(plan.state_indices.iter()) {
            let field = scene.keyboard_map.fields.get(field_slot).context("transaction field slot outside Keyboard Map")?;
            anyhow::ensure!(field.state_index == state_index, "transaction {} field/state slot pairing disagrees with Keyboard Map", plan.id);
        }
    }
    scene.transactions.iter().map(|plan| {
        let tile_mask = tile_mask(&plan.tile_ids, tile_count, &format!("transaction {}", plan.id))?;
        println!("compiler transaction: index={} id={} fields={:?} states={:?} mask=0x{tile_mask:016x}",
                 plan.index, plan.id, plan.field_slots, plan.state_indices);
        Ok(CompiledTransactionPlan { id: plan.id.clone(), field_slots: plan.field_slots.clone(), state_indices: plan.state_indices.clone(), tile_mask })
    }).collect()
}

fn compiler_command_matchers(scene: &Scene, keyboard: Option<&CompiledKeyboardMap>, compiled_actions: &[ActionPlan]) -> Result<Vec<CompiledCommandMatcher>> {
    let Some(keyboard) = keyboard else {
        anyhow::ensure!(scene.command_matchers.is_empty(), "Command Matcher requires a compiler Keyboard Map");
        return Ok(Vec::new());
    };
    let mut seen = HashSet::new();
    let mut compiled = Vec::with_capacity(scene.command_matchers.len());
    for entry in &scene.command_matchers {
        let field = keyboard.fields.get(entry.focus_slot)
            .with_context(|| format!("command matcher {} references focus slot outside Keyboard Map", entry.literal))?;
        anyhow::ensure!(field.node == entry.field && field.charset == "ascii-upper",
                        "command matcher field/focus slot must identify one ascii-upper field");
        let descriptor = field.ascii_text_register.as_ref()
            .context("command matcher field lacks compiler ASCII text register")?;
        anyhow::ensure!(entry.length > 0 && entry.length <= descriptor.max_chars,
                        "command matcher length exceeds fixed text capacity");
        anyhow::ensure!(entry.literal.len() == entry.length && entry.literal.as_bytes().iter().all(|byte| *byte == b' ' || (*byte >= b'A' && *byte <= b'Z')),
                        "command matcher literal must be compiler-supported uppercase ASCII");
        let packed = entry.literal.as_bytes().iter().enumerate().fold(0u64, |value, (index, byte)| value | (u64::from(*byte) << (index * 8)));
        anyhow::ensure!(packed == entry.packed, "command matcher packed literal disagrees with compiler bytes");
        let action = compiled_actions.get(entry.action_index)
            .with_context(|| format!("command matcher {} action_index outside Action Slot table", entry.literal))?;
        let action_slot = scene.action_slots.get(entry.action_index)
            .with_context(|| format!("command matcher {} action slot audit entry missing", entry.literal))?;
        anyhow::ensure!(action_slot.id == entry.action && action_slot.index == entry.action_index,
                        "command matcher action name/index mismatch");
        let tile_count = scene.render_schedules.first().map(|schedule| schedule.tiles.len()).unwrap_or(0);
        let field_mask = field.tile_mask;
        let action_mask = tile_mask(&action.tile_ids, tile_count, "command matcher action")?;
        let matcher_mask = tile_mask(&entry.tile_ids, tile_count, "command matcher")?;
        anyhow::ensure!(matcher_mask == (field_mask | action_mask), "command matcher tile mask must equal field/action union");
        anyhow::ensure!(seen.insert((entry.focus_slot, entry.length, entry.packed)), "duplicate compiler command matcher key");
        println!("compiler command matcher: slot={} field={} literal={} length={} packed=0x{:016x} action={} action_index={} mask=0x{:016x}",
                 entry.focus_slot, entry.field, entry.literal, entry.length, entry.packed, entry.action, entry.action_index, matcher_mask);
        compiled.push(CompiledCommandMatcher { focus_slot: entry.focus_slot, length: entry.length, packed: entry.packed, action: entry.action.clone(), action_index: entry.action_index, tile_mask: matcher_mask });
    }
    compiled.sort_by_key(|entry| (entry.focus_slot, entry.packed));
    Ok(compiled)
}

fn compiler_keyboard_command_map(scene: &Scene, focus: Option<&CompiledFocusGraph>, keyboard: Option<&CompiledKeyboardMap>, transactions: &[CompiledTransactionPlan]) -> Result<Option<CompiledKeyboardCommandMap>> {
    if scene.keyboard_command_map.transitions.is_empty() { return Ok(None); }
    let graph = focus.context("Keyboard Command Map requires Focus Graph")?;
    let keymap = keyboard.context("Keyboard Command Map requires digit Keyboard Map")?;
    let tile_count = scene.render_schedules.first().map(|schedule| schedule.tiles.len()).unwrap_or(0);
    // Host construction uses this same sorted state order; commit admission converts a compiler state symbol to one fixed array index.
    let state_index_by_id: HashMap<String, usize> = scene.state_slots.iter()
        .map(|slot| (slot.id.clone(), slot.index)).collect();
    let mut compiled = Vec::with_capacity(graph.entries.len());
    for slot in 0..graph.entries.len() {
        let field = &keymap.fields[slot];
        let local: Vec<&KeyboardCommandTransition> = scene.keyboard_command_map.transitions.iter()
            .filter(|transition| transition.focus_slot == slot).collect();
        anyhow::ensure!(!local.is_empty() && local.len() <= 2, "Keyboard Command Map slot {slot} must contain Escape and optional Enter");
        let escape = local.iter().find(|transition| transition.key == "escape")
            .context("Keyboard Command Map lacks Escape reset")?;
        anyhow::ensure!(escape.kind == "reset" && escape.action.is_none() && escape.transaction_index.is_none() && escape.target_state.is_none(),
                        "Escape must be compiler reset without action or commit target");
        let escape_mask = tile_mask(&escape.tile_ids, tile_count, "keyboard escape")?;
        anyhow::ensure!(escape_mask == field.tile_mask, "Escape reset tile mask must equal field tile mask");
        let mut transitions = vec![CompiledKeyboardCommandTransition {
            kind: KeyboardCommandKind::Reset, action: None, action_index: None, transaction_index: None, target_state_index: None, tile_mask: escape_mask,
        }];
        if let Some(enter) = local.iter().find(|transition| transition.key == "enter") {
            let enter_mask = tile_mask(&enter.tile_ids, tile_count, "keyboard enter")?;
            match enter.kind.as_str() {
                "action" => {
                    anyhow::ensure!(enter.target_state.is_none(), "action Enter must not carry commit target");
                    let action = enter.action.clone().context("Enter action binding missing")?;
                    let action_index = enter.action_index.context("Enter action_index missing")?;
                    let action_slot = scene.action_slots.get(action_index).context("Enter action_index outside Action Slot table")?;
                    anyhow::ensure!(action_slot.id == action, "Enter action name/index disagree");
                    let action_plan = scene.actions.get(&action).with_context(|| format!("Enter references unknown action {action}"))?;
                    anyhow::ensure!(action_plan.action_index == action_index, "Enter action plan index disagrees with Action Slot");
                    let action_mask = tile_mask(&action_plan.tile_ids, tile_count, "keyboard enter action")?;
                    anyhow::ensure!(enter_mask == field.tile_mask | action_mask, "Enter tile mask must be compiler field/action union");
                    transitions.push(CompiledKeyboardCommandTransition {
                        kind: KeyboardCommandKind::Action, action: Some(action.clone()), action_index: Some(action_index), transaction_index: None, target_state_index: None, tile_mask: enter_mask,
                    });
                    println!("compiler keyboard command: slot={} Enter -> {} mask=0x{:016x}", slot, action, enter_mask);
                }
                "commit-pending-register" => {
                    anyhow::ensure!(enter.action.is_none(), "commit Enter must not reference action plan");
                    let target_state = enter.target_state.clone().context("commit Enter target_state missing")?;
                    anyhow::ensure!(target_state == scene.focus_graph.entries[slot].state,
                                    "commit target state must equal compiler field state for slot {slot}");
                    let target_state_index = *state_index_by_id.get(&target_state)
                        .with_context(|| format!("commit target state {target_state} absent from compiler State Slot table"))?;
                    anyhow::ensure!(enter.target_state_index == Some(target_state_index) &&
                                    target_state_index == scene.focus_graph.entries[slot].state_index,
                                    "commit target state index must equal compiler field State Slot");
                    anyhow::ensure!(enter_mask == field.tile_mask, "commit Enter tile mask must equal field tile mask");
                    transitions.push(CompiledKeyboardCommandTransition {
                        kind: KeyboardCommandKind::CommitPendingRegister, action: None, action_index: None, transaction_index: None,
                        target_state_index: Some(target_state_index), tile_mask: enter_mask,
                    });
                    println!("compiler keyboard command: slot={} Enter -> commit-pending-register state={} index={} mask=0x{:016x}",
                             slot, target_state, target_state_index, enter_mask);
                }
                "commit-group" => {
                    anyhow::ensure!(enter.action.is_none() && enter.target_state.is_none() && enter.target_state_index.is_none(),
                                    "commit-group Enter must not carry action or single-state target");
                    let transaction_index = enter.transaction_index.context("commit-group Enter transaction_index missing")?;
                    let transaction = transactions.get(transaction_index).context("commit-group transaction index outside compiler table")?;
                    anyhow::ensure!(transaction.field_slots.contains(&slot) && enter_mask == transaction.tile_mask,
                                    "commit-group Enter must reference a member field and exact transaction tile union");
                    transitions.push(CompiledKeyboardCommandTransition {
                        kind: KeyboardCommandKind::CommitGroup, action: None, action_index: None,
                        transaction_index: Some(transaction_index), target_state_index: None, tile_mask: enter_mask,
                    });
                    println!("compiler keyboard command: slot={} Enter -> commit-group {} index={} mask=0x{:016x}",
                             slot, transaction.id, transaction_index, enter_mask);
                }
                _ => anyhow::bail!("Enter has unsupported compiler command kind {}", enter.kind),
            }
        }
        anyhow::ensure!(local.iter().all(|transition| transition.key == "escape" || transition.key == "enter"), "Keyboard Command Map contains unsupported key");
        println!("compiler keyboard command: slot={} Escape -> reset mask=0x{:016x}", slot, escape_mask);
        compiled.push(transitions);
    }
    Ok(Some(CompiledKeyboardCommandMap { transitions: compiled }))
}

fn compiler_text_field_visuals(scene: &Scene, focus: Option<&CompiledFocusGraph>, keyboard: Option<&CompiledKeyboardMap>) -> Result<Option<Vec<CompiledTextFieldVisual>>> {
    if scene.text_field_visuals.is_empty() { return Ok(None); }
    let graph = focus.context("text field visual plan requires Focus Graph")?;
    let keymap = keyboard.context("text field visual plan requires Keyboard Map")?;
    anyhow::ensure!(scene.text_field_visuals.len() == graph.entries.len(), "visual plan field count must equal Focus Graph");
    let mut compiled = Vec::with_capacity(graph.entries.len());
    for slot in 0..graph.entries.len() {
        let visual = scene.text_field_visuals.iter().find(|visual| visual.focus_slot == slot)
            .with_context(|| format!("visual plan lacks focus slot {slot}"))?;
        let field = &keymap.fields[slot];
        anyhow::ensure!(visual.node == field.node && visual.max_chars == field.max_chars,
                        "visual plan node/max_chars disagrees with Keyboard Map for slot {slot}");
        anyhow::ensure!(tile_mask(&visual.tile_ids, scene.render_schedules[0].tiles.len(), "text field visual")? == field.tile_mask,
                        "visual plan tile IDs disagree with compiler focus tile");
        anyhow::ensure!(visual.caret_ndc_x_positions.len() == visual.max_chars + 1,
                        "visual plan caret position table must contain cursor 0..max_chars");
        anyhow::ensure!(visual.blink_track.period_ms > 0 && visual.blink_track.alpha[0] >= 0.0 && visual.blink_track.alpha[1] >= 0.0,
                        "visual plan blink track must be fixed and non-negative");
        let max = scene.resource_budget.instance_capacity * std::mem::size_of::<QuadInstance>();
        for offset in [visual.focus_alpha_offset, visual.placeholder_alpha_offset, visual.caret_pos_x_offset, visual.caret_alpha_offset] {
            anyhow::ensure!(offset < max && offset % 4 == 0, "visual plan instance field offset is invalid");
        }
        anyhow::ensure!(visual.focus_alpha_offset == visual.focus_instance_offset + 28 &&
                        visual.placeholder_alpha_offset == visual.placeholder_instance_offset + 28 &&
                        visual.caret_alpha_offset == visual.caret_instance_offset + 28 &&
                        visual.caret_pos_x_offset == visual.caret_instance_offset,
                        "visual plan must use fixed QuadInstance alpha/pos.x ABI");
        println!("compiler text field visual: slot={} node={} blink={}ms track={}", slot, visual.node, visual.blink_track.period_ms, visual.blink_track.id);
        compiled.push(CompiledTextFieldVisual { tile_mask: field.tile_mask, max_chars: visual.max_chars,
            focus_alpha_offset: visual.focus_alpha_offset as u64, placeholder_alpha_offset: visual.placeholder_alpha_offset as u64,
            caret_pos_x_offset: visual.caret_pos_x_offset as u64, caret_alpha_offset: visual.caret_alpha_offset as u64,
            caret_ndc_x_positions: visual.caret_ndc_x_positions.clone(), blink_period_ms: visual.blink_track.period_ms, blink_alpha: visual.blink_track.alpha });
    }
    Ok(Some(compiled))
}

fn compiler_tile_selection(scene: &Scene) -> Result<(HashMap<String, u64>, Vec<EventTileMasks>)> {
    let schedule = scene.render_schedules.first().context("compiler scene has no render schedule for tile selection")?;
    let tile_count = schedule.tiles.len();
    let mut action_masks = HashMap::new();
    for (action_id, action) in &scene.actions {
        let owner = format!("action {action_id}");
        action_masks.insert(action_id.clone(), tile_mask(&action.tile_ids, tile_count, &owner)?);
    }
    let task_by_id: HashMap<&str, &FrameTask> = scene.frame_schedule.iter()
        .map(|task| (task.id.as_str(), task)).collect();
    let task_mask = |task_id: String, expected_kind: &str| -> Result<u64> {
        let task = task_by_id.get(task_id.as_str())
            .with_context(|| format!("compiler scene has no frame task {task_id}"))?;
        anyhow::ensure!(task.kind == expected_kind, "frame task {task_id} kind {} expected {expected_kind}", task.kind);
        tile_mask(&task.tile_ids, tile_count, &format!("frame task {task_id}"))
    };
    let event_masks = scene.event_map.iter().map(|event| {
        Ok(EventTileMasks {
            hover: task_mask(format!("hover-{}", event.node), "hover")?,
            _pressed: task_mask(format!("pressed-{}", event.node), "pressed")?,
            release: task_mask(format!("release-{}", event.node), "release")?,
        })
    }).collect::<Result<Vec<_>>>()?;
    Ok((action_masks, event_masks))
}

fn task_winner_id(left: &FrameTask, right: &FrameTask) -> String {
    if left.priority > right.priority { left.id.clone() }
    else if left.priority < right.priority { right.id.clone() }
    else if left.id < right.id { left.id.clone() }
    else { right.id.clone() }
}

fn range_is_owned_by(ranges: &[ByteRange], offset: usize, byte_length: usize) -> bool {
    ranges.iter().any(|range| range.offset <= offset && offset + byte_length <= range.offset + range.byte_length)
}

fn compiler_strategy_for_batch(batch: &FrameCoalescedBatch) -> Result<CompilerStrategy> {
    let strategy = CompilerStrategy::parse(&batch.strategy_id)?;
    let is_activate = batch.id.starts_with("coalesced-activate-");
    match (is_activate, batch.selection_proof.as_ref()) {
        (false, None) => {
            anyhow::ensure!(strategy == CompilerStrategy::Coalesced, "non-activate batch {} must retain the coalesced executor", batch.id);
        }
        (false, Some(proof)) => {
            anyhow::ensure!(proof.mode == "non-activate-batch" && strategy == CompilerStrategy::Coalesced,
                            "non-activate batch {} has an invalid strategy proof", batch.id);
        }
        (true, Some(proof)) if proof.mode == "profile-unavailable" => {
            anyhow::ensure!(strategy == CompilerStrategy::Coalesced,
                            "profile-unavailable activate batch {} may only use the conservative coalesced executor", batch.id);
        }
        (true, Some(proof)) if proof.mode == "profile-guided" => {
            anyhow::ensure!(proof.semantic_group.as_deref() == Some("complete-activate-v1"),
                            "activate batch {} has an invalid semantic group", batch.id);
            anyhow::ensure!(proof.selection_metric.as_deref() == Some("gpu_median_ns"),
                            "activate batch {} has an invalid selection metric", batch.id);
            anyhow::ensure!(proof.source_batch.as_deref() == Some(batch.id.as_str()),
                            "activate batch {} proof source_batch disagrees", batch.id);
            anyhow::ensure!(proof.winner.as_deref() == Some(batch.strategy_id.as_str()),
                            "activate batch {} proof winner disagrees with strategy_id", batch.id);
            anyhow::ensure!(proof.tie_break_order == vec!["full-redraw", "packet-aware", "coalesced"],
                            "activate batch {} has an invalid compiler tie-break order", batch.id);
            let required = ["full-redraw", "packet-aware", "coalesced"];
            anyhow::ensure!(batch.candidate_costs.len() == required.len()
                            && required.iter().all(|id| batch.candidate_costs.contains_key(*id)),
                            "activate batch {} must provide exactly three semantic-equivalent replay costs", batch.id);
            anyhow::ensure!(!batch.candidate_costs.contains_key("action-aware"),
                            "activate batch {} illegally includes action-aware in its complete visual strategy set", batch.id);
            let selected_cost = *batch.candidate_costs.get(&batch.strategy_id)
                .with_context(|| format!("activate batch {} has no selected strategy cost", batch.id))?;
            anyhow::ensure!(selected_cost.is_finite() && selected_cost >= 0.0,
                            "activate batch {} selected strategy cost is invalid", batch.id);
            for (id, cost) in &batch.candidate_costs {
                anyhow::ensure!(cost.is_finite() && *cost >= 0.0,
                                "activate batch {} candidate {id} has invalid cost", batch.id);
                anyhow::ensure!(selected_cost <= *cost,
                                "activate batch {} strategy_id is not the compiler-proven minimum", batch.id);
            }
            println!("compiler strategy proof: batch={} profile={} strategy={} metric=gpu_median_ns", batch.id,
                     proof.profile_id.as_deref().unwrap_or("none"), strategy.id());
        }
        (true, Some(proof)) => anyhow::bail!("activate batch {} has unsupported proof mode {}", batch.id, proof.mode),
        (true, None) => anyhow::bail!("activate batch {} is missing compiler strategy proof", batch.id),
    }
    Ok(strategy)
}

fn compiler_coalesced_batches(scene: &Scene) -> Result<(HashMap<String, CompiledBatch>, Vec<EventBatchIds>, HashMap<String, usize>, Vec<String>)> {
    let schedule = scene.render_schedules.first().context("compiler scene has no render schedule for coalesced batches")?;
    let tile_count = schedule.tiles.len();
    let task_by_id: HashMap<&str, &FrameTask> = scene.frame_schedule.iter()
        .map(|task| (task.id.as_str(), task)).collect();
    let action_index_by_id: HashMap<&str, usize> = scene.action_slots.iter()
        .map(|slot| (slot.id.as_str(), slot.index)).collect();
    let transient_task_ids: Vec<String> = scene.frame_schedule.iter()
        .filter(|task| !action_index_by_id.contains_key(task.id.as_str()))
        .map(|task| task.id.clone()).collect::<Vec<_>>();
    let mut transient_task_ids = transient_task_ids;
    transient_task_ids.sort();
    let mut compiled = HashMap::new();

    for batch in &scene.frame_coalesced_batches {
        anyhow::ensure!(!batch.task_ids.is_empty(), "coalesced batch {} has no member tasks", batch.id);
        let members: Vec<&FrameTask> = batch.task_ids.iter().map(|task_id| {
            task_by_id.get(task_id.as_str()).copied()
                .with_context(|| format!("coalesced batch {} references unknown task {task_id}", batch.id))
        }).collect::<Result<Vec<_>>>()?;
        let mut expected_order = members.clone();
        expected_order.sort_by(|left, right| left.priority.cmp(&right.priority).then_with(|| left.id.cmp(&right.id)));
        let expected_ids: Vec<String> = expected_order.iter().map(|task| task.id.clone()).collect();
        anyhow::ensure!(batch.execution_order == expected_ids, "coalesced batch {} execution_order disagrees with compiler priority contract", batch.id);
        anyhow::ensure!(batch.execution_refs.len() == expected_ids.len(), "coalesced batch {} task-ref count disagrees with execution order", batch.id);
        let mut execution_refs = Vec::with_capacity(batch.execution_refs.len());
        let mut task_worklist_indices = Vec::with_capacity(batch.execution_refs.len());
        for (expected_id, task_ref) in expected_ids.iter().zip(batch.execution_refs.iter()) {
            anyhow::ensure!(&task_ref.id == expected_id, "coalesced batch {} task-ref audit ID disagrees with execution order", batch.id);
            let task = task_by_id.get(expected_id.as_str()).expect("batch member admission already proved task");
            anyhow::ensure!(task.packet_worklist_index < scene.packet_worklists.len(),
                            "coalesced batch {} task {} has worklist index outside compiler table", batch.id, expected_id);
            task_worklist_indices.push(task.packet_worklist_index);
            match task_ref.kind.as_str() {
                "action" => {
                    anyhow::ensure!(task.kind == "action", "coalesced batch {} action ref points to non-action task {}", batch.id, expected_id);
                    let slot = scene.action_slots.get(task_ref.index).context("coalesced action index outside Action Slot table")?;
                    anyhow::ensure!(slot.id == task_ref.id && action_index_by_id.get(task_ref.id.as_str()) == Some(&task_ref.index),
                                    "coalesced batch {} action task-ref name/index mismatch", batch.id);
                    execution_refs.push(CompiledTaskRef::Action(task_ref.index));
                }
                "transaction" => {
                    anyhow::ensure!(task.kind == "transaction", "coalesced batch {} transaction ref points to non-transaction task {}", batch.id, expected_id);
                    let transaction = scene.transactions.get(task_ref.index).context("coalesced transaction index outside compiler table")?;
                    anyhow::ensure!(transaction.index == task_ref.index && task_ref.id == format!("transaction-{}", task_ref.index),
                                    "coalesced batch {} transaction task-ref name/index mismatch", batch.id);
                    execution_refs.push(CompiledTaskRef::Transaction(task_ref.index));
                }
                "transient" => {
                    anyhow::ensure!(task.kind != "action" && task.kind != "transaction", "coalesced batch {} transient ref points to business task {}", batch.id, expected_id);
                    let transient_id = transient_task_ids.get(task_ref.index).context("coalesced transient index outside transient task table")?;
                    anyhow::ensure!(transient_id == &task_ref.id, "coalesced batch {} transient task-ref name/index mismatch", batch.id);
                    execution_refs.push(CompiledTaskRef::Transient(task_ref.index));
                }
                _ => anyhow::bail!("coalesced batch {} has unsupported task-ref kind {}", batch.id, task_ref.kind),
            }
        }
        // Recompute the compiler claim from immutable member task slots.  A batch-local
        // slot is accepted only when it is exactly the sorted, deduplicated packet union;
        // it may never widen the compute prepass beyond its constituent dependencies.
        let packet_indices_for_slot = |slot: usize| -> Result<Vec<usize>> {
            scene.packet_worklists.iter().find(|worklist| worklist.index == slot)
                .map(|worklist| worklist.packet_indices.clone())
                .with_context(|| format!("coalesced batch {} refers to missing worklist slot {slot}", batch.id))
        };
        let mut expected_member_slots: Vec<usize> = expected_ids.iter()
            .flat_map(|task_id| {
                let task = task_by_id.get(task_id.as_str()).expect("batch member admission already proved task");
                if task.packet_worklist_indices.is_empty() {
                    vec![task.packet_worklist_index]
                } else {
                    task.packet_worklist_indices.clone()
                }
            })
            .filter(|slot| !packet_indices_for_slot(*slot).expect("member slot admitted above").is_empty())
            .collect();
        expected_member_slots.sort_unstable();
        expected_member_slots.dedup();
        let mut expected_packets: Vec<usize> = expected_member_slots.iter()
            .map(|slot| packet_indices_for_slot(*slot))
            .collect::<Result<Vec<_>>>()?
            .into_iter().flatten().collect();
        expected_packets.sort_unstable();
        expected_packets.dedup();
        let legacy_slot = expected_member_slots.last().copied().unwrap_or(RenderRequest::NO_PACKETS);
        let composite_worklist_index = batch.composite_worklist_index.unwrap_or(legacy_slot);
        let selected_packets = packet_indices_for_slot(composite_worklist_index)?;
        if batch.composite_worklist_index.is_some() {
            anyhow::ensure!(batch.composite_worklist_member_indices == expected_member_slots,
                            "coalesced batch {} composite member slots disagree with task-local dependencies", batch.id);
            anyhow::ensure!(batch.composite_worklist_packet_indices == expected_packets,
                            "coalesced batch {} composite packet proof disagrees with member slot union", batch.id);
            anyhow::ensure!(selected_packets == expected_packets,
                            "coalesced batch {} selected composite worklist is not the exact packet union", batch.id);
            if expected_member_slots.len() > 1 {
                let selected = scene.packet_worklists.iter().find(|worklist| worklist.index == composite_worklist_index)
                    .expect("selected worklist admitted above");
                anyhow::ensure!(selected.id.starts_with("batch-"),
                                "coalesced batch {} multi-slot union must select a compiler batch-local worklist", batch.id);
                let fusion = batch.batch_fusion_proof.as_ref()
                    .with_context(|| format!("coalesced batch {} is missing compiler batch-fusion proof", batch.id))?;
                anyhow::ensure!(fusion.member_worklist_indices == expected_member_slots
                                && fusion.fused_worklist_index == composite_worklist_index
                                && fusion.fused_packet_indices == expected_packets
                                && fusion.fused_tile_ids == batch.merged_tile_ids
                                && fusion.strategy_id == batch.strategy_id,
                                "coalesced batch {} batch-fusion proof disagrees with immutable batch artifact", batch.id);
            }
        }
        let fusion_baseline_requests = if expected_member_slots.len() > 1 {
            let fusion = batch.batch_fusion_proof.as_ref()
                .with_context(|| format!("coalesced batch {} is missing compiler batch-fusion proof", batch.id))?;
            anyhow::ensure!(fusion.baseline_requests.len() == expected_member_slots.len(),
                            "coalesced batch {} baseline request count disagrees with member slots", batch.id);
            let mut baseline_tiles = Vec::new();
            let mut compiled_requests = Vec::with_capacity(fusion.baseline_requests.len());
            for (expected_slot, request) in expected_member_slots.iter().zip(fusion.baseline_requests.iter()) {
                anyhow::ensure!(request.worklist_index == *expected_slot,
                                "coalesced batch {} baseline request slot order disagrees with member slots", batch.id);
                anyhow::ensure!(packet_indices_for_slot(request.worklist_index)?.len() == 1,
                                "coalesced batch {} baseline request must remain field-local", batch.id);
                let request_mask = tile_mask(&request.tile_ids, tile_count,
                                             &format!("coalesced batch {} baseline request", batch.id))?;
                baseline_tiles.extend(request.tile_ids.iter().copied());
                compiled_requests.push(CompiledFusionBaselineRequest {
                    tile_mask: request_mask,
                    packet_worklist_index: request.worklist_index,
                });
            }
            let mut expected_tiles = batch.merged_tile_ids.clone();
            expected_tiles.sort_unstable();
            baseline_tiles.sort_unstable();
            anyhow::ensure!(baseline_tiles.len() == baseline_tiles.iter().copied().collect::<HashSet<_>>().len()
                            && baseline_tiles == expected_tiles,
                            "coalesced batch {} baseline tile partition is not an exact non-overlapping union", batch.id);
            compiled_requests
        } else {
            Vec::new()
        };
        let composite_worklist_packet_indices = selected_packets.into_iter().map(|packet| packet as u32).collect();
        let member_ids: HashMap<&str, &FrameTask> = members.iter().map(|task| (task.id.as_str(), *task)).collect();
        let mask = tile_mask(&batch.merged_tile_ids, tile_count, &format!("coalesced batch {}", batch.id))?;
        let strategy = compiler_strategy_for_batch(batch)?;
        if let Some(admission) = batch.selection_proof.as_ref().and_then(|proof| proof.fusion_admission.as_ref()) {
            anyhow::ensure!(matches!(admission.status.as_str(), "admitted" | "rejected"),
                            "coalesced batch {} has unsupported fusion admission status {}", batch.id, admission.status);
            let expected_task_ids: Vec<String> = std::iter::once(admission.release_task.clone())
                .chain(admission.action_ids.iter().cloned()).collect();
            anyhow::ensure!(batch.task_ids == expected_task_ids,
                            "coalesced batch {} fusion admission task membership disagrees with batch", batch.id);
            anyhow::ensure!(batch.execution_order.first() == Some(&admission.release_task),
                            "coalesced batch {} fusion admission release task is not first", batch.id);
            anyhow::ensure!(admission.action_tile_ids.len() == admission.action_ids.len()
                            && admission.packet_worklist_indices.len() == admission.action_ids.len(),
                            "coalesced batch {} fusion admission action vectors have inconsistent lengths", batch.id);
            let mut admission_tiles = Vec::new();
            let mut action_conflicts = 0usize;
            for (index, action_id) in admission.action_ids.iter().enumerate() {
                let task = task_by_id.get(action_id.as_str())
                    .with_context(|| format!("coalesced batch {} fusion admission references unknown action {}", batch.id, action_id))?;
                anyhow::ensure!(task.kind == "action" && task.tile_ids == admission.action_tile_ids[index]
                                && task.packet_worklist_index == admission.packet_worklist_indices[index],
                                "coalesced batch {} fusion admission action artifact disagrees with task {}", batch.id, action_id);
                admission_tiles.extend(task.tile_ids.iter().copied());
            }
            for left in 0..admission.action_ids.len() {
                for right in left + 1..admission.action_ids.len() {
                    let left_task = task_by_id.get(admission.action_ids[left].as_str()).expect("action admitted above");
                    let right_task = task_by_id.get(admission.action_ids[right].as_str()).expect("action admitted above");
                    if left_task.writes.iter().any(|lw| right_task.writes.iter().any(|rw| lw.offset < rw.offset + rw.byte_length && rw.offset < lw.offset + lw.byte_length)) {
                        action_conflicts += 1;
                    }
                }
            }
            anyhow::ensure!(action_conflicts == admission.conflict_edge_count,
                            "coalesced batch {} fusion admission conflict count disagrees with task writes", batch.id);
            if admission.status == "admitted" {
                anyhow::ensure!(admission.reason == "unknown" && admission.strategy_id == batch.strategy_id
                                && strategy == CompilerStrategy::Coalesced
                                && admission.packet_worklist_indices.iter().all(|slot| *slot == RenderRequest::NO_PACKETS)
                                && admission_tiles.len() == admission_tiles.iter().copied().collect::<HashSet<_>>().len(),
                                "coalesced batch {} admitted fusion proof violates compiler invariants", batch.id);
            } else {
                anyhow::ensure!(matches!(admission.reason.as_str(), "task-membership" | "animation-order" | "write-conflict" | "tile-overlap" | "packet-scope"),
                                "coalesced batch {} rejected fusion proof has unsupported reason {}", batch.id, admission.reason);
            }
        }

        for write in &batch.winner_writes {
            let owner = member_ids.get(write.task_id.as_str())
                .with_context(|| format!("coalesced batch {} winner write has external task {}", batch.id, write.task_id))?;
            anyhow::ensure!(range_is_owned_by(&owner.writes, write.offset, write.byte_length), "coalesced batch {} winner write {} [{}..{}) escapes source task range", batch.id, write.task_id, write.offset, write.offset + write.byte_length);
        }
        for eliminated in &batch.eliminated_writes {
            let loser = member_ids.get(eliminated.task_id.as_str())
                .with_context(|| format!("coalesced batch {} eliminated write has external task {}", batch.id, eliminated.task_id))?;
            let winner = member_ids.get(eliminated.winner.as_str())
                .with_context(|| format!("coalesced batch {} elimination winner {} is external", batch.id, eliminated.winner))?;
            anyhow::ensure!(range_is_owned_by(&loser.writes, eliminated.offset, eliminated.byte_length)
                            && range_is_owned_by(&winner.writes, eliminated.offset, eliminated.byte_length),
                            "coalesced batch {} elimination [{}..{}) is not jointly owned", batch.id, eliminated.offset, eliminated.offset + eliminated.byte_length);
            anyhow::ensure!(task_winner_id(loser, winner) == winner.id, "coalesced batch {} elimination winner violates priority proof", batch.id);
        }
        for edge in &batch.conflict_edges {
            let left = member_ids.get(edge.left.as_str()).with_context(|| format!("coalesced batch {} conflict left external", batch.id))?;
            let right = member_ids.get(edge.right.as_str()).with_context(|| format!("coalesced batch {} conflict right external", batch.id))?;
            anyhow::ensure!(task_winner_id(left, right) == edge.winner, "coalesced batch {} conflict winner disagrees with priority", batch.id);
            for overlap in &edge.overlaps {
                anyhow::ensure!(range_is_owned_by(&left.writes, overlap.offset, overlap.byte_length)
                                && range_is_owned_by(&right.writes, overlap.offset, overlap.byte_length),
                                "coalesced batch {} conflict overlap is not jointly owned", batch.id);
            }
        }
        anyhow::ensure!(compiled.insert(batch.id.clone(), CompiledBatch {
            id: batch.id.clone(), execution_refs, task_worklist_indices,
            composite_worklist_index, composite_worklist_member_indices: expected_member_slots,
            composite_worklist_packet_indices, fusion_baseline_requests,
            winner_writes: batch.winner_writes.clone(), tile_mask: mask, strategy,
        }).is_none(), "duplicate compiler coalesced batch ID {}", batch.id);
    }

    let mut frame_task_event_slots = HashMap::new();
    let event_batches = scene.event_map.iter().enumerate().map(|(slot, event)| {
        let press = format!("coalesced-press-{}", event.node);
        let activate = format!("coalesced-activate-{}", event.node);
        let release = format!("release-{}", event.node);
        for kind in ["hover", "pressed", "release"] {
            let task_id = format!("{kind}-{}", event.node);
            anyhow::ensure!(task_by_id.contains_key(task_id.as_str()), "event {} has no frame task {task_id}", event.node);
            anyhow::ensure!(frame_task_event_slots.insert(task_id, slot).is_none(), "duplicate compiler frame task/event binding");
        }
        anyhow::ensure!(compiled.contains_key(&press) && compiled.contains_key(&activate), "event {} has no compiler coalesced batch pair", event.node);
        Ok(EventBatchIds { press, activate, release })
    }).collect::<Result<Vec<_>>>()?;
    Ok((compiled, event_batches, frame_task_event_slots, transient_task_ids))
}

// `glyph_packet_ranges` 是 compiler 给出的执行计划，而非可选提示。宿主只检查 ABI
// 不变量，不做 packet-vs-tile 或 glyph-vs-tile 几何搜索。
fn compiler_packet_worklists(scene: &Scene, packets: &[CompiledSubgroupPacket]) -> Result<Vec<CompiledPacketWorklist>> {
    anyhow::ensure!(scene.packet_worklists.len() >= 3, "Noir packet worklist ABI requires all/dynamic/no-packets baselines");
    let mut result = Vec::with_capacity(scene.packet_worklists.len());
    for (expected_index, entry) in scene.packet_worklists.iter().enumerate() {
        anyhow::ensure!(entry.index == expected_index, "packet worklist index is not dense");
        let expected_id = match expected_index { 0 => "all-packets", 1 => "dynamic-packets", 2 => "no-packets", _ => "" };
        if expected_index < 3 { anyhow::ensure!(entry.id == expected_id, "packet worklist canonical id mismatch"); }
        anyhow::ensure!(entry.packet_indices.iter().all(|&index| index < packets.len()), "packet worklist references packet out of range");
        anyhow::ensure!(entry.packet_indices.len() == entry.packet_indices.iter().copied().collect::<std::collections::BTreeSet<_>>().len(), "packet worklist contains duplicate packet index");
        result.push(CompiledPacketWorklist { index: entry.index, id: entry.id.clone(), packet_indices: entry.packet_indices.iter().map(|&index| index as u32).collect() });
    }
    anyhow::ensure!(result[0].packet_indices == (0..packets.len() as u32).collect::<Vec<_>>(), "all-packets worklist must cover compiler packet table densely");
    let expected_dynamic: Vec<u32> = packets.iter().filter(|packet| packet.dynamic).map(|packet| packet.index as u32).collect();
    anyhow::ensure!(result[1].packet_indices == expected_dynamic, "dynamic-packets worklist must equal compiler dynamic packet closure");
    anyhow::ensure!(result[2].packet_indices.is_empty(), "no-packets worklist must be compiler-fixed empty set");
    let mut ids = std::collections::BTreeSet::new();
    anyhow::ensure!(result.iter().all(|worklist| ids.insert(worklist.id.clone())), "packet worklist IDs must be unique");
    Ok(result)
}

fn compiler_keyboard_packet_worklists(keyboard: Option<&CompiledKeyboardMap>, lists: &[CompiledPacketWorklist]) -> Result<Vec<usize>> {
    let Some(keyboard) = keyboard else { return Ok(Vec::new()); };
    keyboard.fields.iter().map(|field| {
        let id = format!("field-{}", field.node);
        let index = lists.iter().position(|worklist| worklist.id == id)
            .with_context(|| format!("Keyboard field {} lacks compiler local packet worklist", field.node))?;
        anyhow::ensure!(lists[index].packet_indices.len() <= 32, "field worklist exceeds fixed uniform capacity");
        Ok(index)
    }).collect()
}

fn compiler_transaction_packet_worklists(transactions: &[CompiledTransactionPlan], lists: &[CompiledPacketWorklist]) -> Result<Vec<usize>> {
    transactions.iter().map(|plan| {
        let id = format!("transaction-{}", plan.id);
        let index = lists.iter().position(|worklist| worklist.id == id)
            .with_context(|| format!("Transaction {} lacks compiler local packet worklist", plan.id))?;
        anyhow::ensure!(lists[index].packet_indices.len() <= 32, "transaction worklist exceeds fixed uniform capacity");
        Ok(index)
    }).collect()
}

fn compiler_packet_activity_contract(scene: &Scene, packets: &[CompiledSubgroupPacket]) -> Result<()> {
    let contract = scene.packet_activity_contract.as_ref().context("Scene lacks compiler packet activity variant contract")?;
    anyhow::ensure!(contract.packet_count == packets.len() && contract.workgroup_size == 32,
                    "packet activity contract packet count/workgroup width disagrees with compiler packet plan");
    anyhow::ensure!(contract.scalar_entry == "packet_activity" && contract.subgroup_entry == "packet_activity_subgroup",
                    "packet activity contract has noncanonical WGSL entry names");
    anyhow::ensure!(contract.differential_required,
                    "Noir packet activity contract must require scalar/subgroup differential admission");
    Ok(())
}

fn compiler_subgroup_packets(scene: &Scene) -> Result<Vec<CompiledSubgroupPacket>> {
    let mut expected_index = 0usize;
    let mut expected_first_by_packet: HashMap<usize, u32> = scene.glyph_draw_packets.iter()
        .enumerate().map(|(index, packet)| (index, packet.first_placement)).collect();
    let mut compiled = Vec::with_capacity(scene.subgroup_packet_plan.len());
    for packet in &scene.subgroup_packet_plan {
        anyhow::ensure!(packet.index == expected_index, "subgroup packet index must be dense");
        expected_index += 1;
        anyhow::ensure!(packet.packet_index < scene.glyph_draw_packets.len(), "subgroup packet references glyph draw packet outside Scene");
        let source = &scene.glyph_draw_packets[packet.packet_index];
        anyhow::ensure!(packet.packet_id == source.id && packet.dynamic == source.dynamic,
                        "subgroup packet audit ID/dynamic flag disagrees with glyph draw packet");
        anyhow::ensure!(packet.subgroup_width == 32 && packet.lane_count > 0 && packet.lane_count <= 32,
                        "Noir subgroup packet must have a fixed width-32, nonempty lane plan");
        let mask = if packet.lane_count == 32 { u32::MAX } else { (1u32 << packet.lane_count) - 1 };
        anyhow::ensure!(packet.active_lane_mask == mask, "subgroup packet active lane mask disagrees with lane count");
        anyhow::ensure!(packet.activity_word_offset == packet.index && packet.indirect_byte_offset == (packet.index as u64) * 16,
                        "subgroup packet activity/indirect offsets disagree with canonical GPU ABI");
        let expected_first = expected_first_by_packet.get_mut(&packet.packet_index)
            .context("subgroup packet source interval missing")?;
        anyhow::ensure!(packet.first_placement == *expected_first,
                        "subgroup packet placement range is not contiguous within source glyph packet");
        *expected_first += packet.lane_count;
        let source_end = source.first_placement + source.placement_count;
        anyhow::ensure!(*expected_first <= source_end, "subgroup packet exceeds source glyph draw packet");
        compiled.push(CompiledSubgroupPacket { index: packet.index, packet_index: packet.packet_index, first_placement: packet.first_placement, lane_count: packet.lane_count, active_lane_mask: packet.active_lane_mask, activity_word_offset: packet.activity_word_offset, indirect_byte_offset: packet.indirect_byte_offset as u64, dynamic: packet.dynamic });
    }
    for (packet_index, expected_end) in expected_first_by_packet {
        let source = &scene.glyph_draw_packets[packet_index];
        anyhow::ensure!(expected_end == source.first_placement + source.placement_count,
                        "subgroup packets do not completely cover compiler glyph draw packet");
    }
    Ok(compiled)
}

fn validate_tile_glyph_ranges(scene: &Scene) -> Result<(usize, u32)> {
    let mut range_count = 0usize;
    let mut instance_count = 0u32;
    for (tile_index, tile) in scene.render_schedules.iter().flat_map(|schedule| schedule.tiles.iter()).enumerate() {
        let tile_bounds = [tile.x, tile.y, tile.width, tile.height];
        let mut prior_end_by_packet: HashMap<usize, u32> = HashMap::new();
        for range in &tile.glyph_packet_ranges {
            anyhow::ensure!(range.packet_index < scene.glyph_draw_packets.len(), "tile {tile_index} references packet index {} outside compiler packet table", range.packet_index);
            let packet = &scene.glyph_draw_packets[range.packet_index];
            anyhow::ensure!(range.packet_id == packet.id, "tile {tile_index} range packet ID {} disagrees with packet index {}", range.packet_id, range.packet_index);
            let packet_end = packet.first_placement + packet.placement_count;
            let range_end = range.first_placement + range.placement_count;
            anyhow::ensure!(range.placement_count > 0 && range.first_placement >= packet.first_placement && range_end <= packet_end, "tile {tile_index} range {} escapes packet {} placement interval", range.packet_id, range.packet_index);
            anyhow::ensure!(range.dynamic == packet.dynamic, "tile {tile_index} range {} dynamic flag disagrees with packet", range.packet_id);
            anyhow::ensure!(rects_intersect(packet.bounds, tile_bounds) && rects_intersect(range.bounds, tile_bounds), "tile {tile_index} range {} has no compiler bounds intersection", range.packet_id);
            if let Some(prior_end) = prior_end_by_packet.insert(range.packet_index, range_end) {
                anyhow::ensure!(prior_end <= range.first_placement, "tile {tile_index} contains overlapping/non-monotonic subranges for packet {}", range.packet_index);
            }
            range_count += 1;
            instance_count += range.placement_count;
        }
    }
    Ok((range_count, instance_count))
}

fn placement_instances(scene:&Scene)->Result<Vec<GlyphPlacementInstance>>{
    anyhow::ensure!(!scene.glyph_placement_plan.is_empty(), "Scene has no compiler glyph placement plan");
    anyhow::ensure!(scene.glyph_placement_plan.len()==scene.resource_budget.glyph_capacity, "compiler glyph placement count disagrees with glyph capacity");
    // A compact data-register is a second, compiler-proved mutability source: it
    // may patch only the preallocated glyph cells of its physical row ring. Build
    // the admitted address set once during startup proof; no runtime event path
    // reconstructs or searches it.
    let compact_register_slots = scene.virtual_list_plans.iter()
        .filter(|plan| plan.data_register_table.is_some())
        .flat_map(|plan| plan.row_glyph_slots.iter().flatten().copied())
        .collect::<HashSet<_>>();
    let dynamic_font_cell_slots = scene.dynamic_font_cell_plan.as_ref().map(|plan| {
        plan.tables.iter().flat_map(|table| table.placement_slots.iter().copied()).collect::<HashSet<_>>()
    }).unwrap_or_default();
    let dynamic_font_face = scene.dynamic_font_cell_plan.as_ref().map(|plan| plan.face_id.as_str());
    let mut instances=Vec::with_capacity(scene.glyph_placement_plan.len());
    for(entry_slot,entry)in scene.glyph_placement_plan.iter().enumerate(){
        anyhow::ensure!(entry.slot==entry_slot, "placement {} ({}) has non-dense slot {}", entry.node, entry.glyph_index, entry.slot);
        anyhow::ensure!(entry.glyph_byte_offset==entry.slot*GLYPH_CELL_BYTES, "placement {} has invalid glyph byte offset", entry.node);
        anyhow::ensure!(entry.glyph_word_offset==entry.glyph_byte_offset/4, "placement {} has invalid glyph word offset", entry.node);
        anyhow::ensure!(entry.glyph_id>>16==entry.atlas_page, "placement {} glyph ID page mismatch", entry.node);
        anyhow::ensure!(entry.advance>0.0, "placement {} has non-positive advance", entry.node);
        if entry.dynamic {
            if let Some(state_index) = entry.state_index {
                anyhow::ensure!(state_index < scene.state_slots.len(), "dynamic glyph placement {} state_index is outside State Slot table", entry.node);
            } else {
                let legacy_allowed = compact_register_slots.contains(&entry.slot)
                    && entry.atlas_page == 1 && entry.face_id.is_none();
                let page3_allowed = dynamic_font_cell_slots.contains(&entry.slot)
                    && entry.atlas_page == 3 && entry.face_id.as_deref() == dynamic_font_face
                    && entry.glyph_id >> 16 == 3 && (entry.glyph_id & 0xffff) < 37
                    && (entry.advance - 10.0).abs() <= 1e-6;
                anyhow::ensure!(legacy_allowed || page3_allowed,
                                "state-free dynamic placement {} is not an admitted compact data-register legacy or dynamic page-3 cell", entry.node);
            }
        } else {
            anyhow::ensure!(entry.state_index.is_none(), "static glyph placement {} must not carry State Slot index", entry.node);
        }
        let glyph_word_offset=if entry.dynamic {entry.glyph_word_offset as u32}else{STATIC_GLYPH_WORD_OFFSET};
        instances.push(GlyphPlacementInstance{pos:entry.ndc_pos,size:entry.ndc_size,atlas_uv:entry.atlas_uv,glyph_word_offset,atlas_page:entry.atlas_page,dynamic:u32::from(entry.dynamic),alpha:1.0});
    }
    let mut expected=0u32;
    for packet in &scene.glyph_draw_packets{
        anyhow::ensure!(packet.first_placement==expected, "packet {} does not begin at the next placement", packet.id);
        anyhow::ensure!(packet.placement_count>0, "packet {} is empty", packet.id);
        anyhow::ensure!(packet.first_glyph_byte_offset==packet.first_placement as usize*GLYPH_CELL_BYTES, "packet {} has invalid byte origin", packet.id);
        anyhow::ensure!(packet.glyph_byte_length==packet.placement_count as usize*GLYPH_CELL_BYTES, "packet {} has invalid byte length", packet.id);
        let range=packet.first_placement as usize..(packet.first_placement+packet.placement_count) as usize;
        anyhow::ensure!(range.end<=scene.glyph_placement_plan.len(), "packet {} exceeds placement buffer", packet.id);
        anyhow::ensure!(!packet.nodes.is_empty(), "packet {} has no source node", packet.id);
        anyhow::ensure!(scene.glyph_placement_plan[range.clone()].iter().all(|placement| placement.atlas_page==packet.atlas_page && placement.dynamic==packet.dynamic), "packet {} disagrees with placement page/dynamic contract", packet.id);
        expected+=packet.placement_count;
    }
    anyhow::ensure!(expected as usize==instances.len(), "glyph packets do not cover the placement buffer");
    Ok(instances)
}

fn digit_ids(value:i64,count:usize)->Result<Vec<u32>>{anyhow::ensure!(value>=0,"negative glyph value");let text=format!("{:0width$}",value,width=count);anyhow::ensure!(text.len()<=count,"glyph width overflow");Ok(text.bytes().map(|digit|(digit-b'0')as u32).collect())}
fn initial_glyph_bytes(scene:&Scene)->Result<Vec<u8>>{let mut bytes=vec![0u8;scene.resource_budget.glyph_capacity.max(1)*GLYPH_CELL_BYTES];if !scene.glyph_placement_plan.is_empty(){for placement in &scene.glyph_placement_plan{let base=placement.glyph_byte_offset;bytes[base..base+4].copy_from_slice(&placement.glyph_id.to_le_bytes());}return Ok(bytes);}for entry in &scene.layout_plan{if !entry.glyph_ids.is_empty(){for(index,glyph)in entry.glyph_ids.iter().enumerate(){let base=entry.glyph_offset+index*GLYPH_CELL_BYTES;bytes[base..base+4].copy_from_slice(&glyph.to_le_bytes());}}}for action in scene.actions.values(){for update in &action.gpu_updates{let value=scene.state_slots.get(update.state_index).with_context(||format!("initial glyph update {} has invalid compiler state_index {}",update.node,update.state_index))?.initial;for(index,glyph_id)in digit_ids(value,update.glyph_count)?.iter().enumerate(){let base=update.offset+index*GLYPH_CELL_BYTES;bytes[base..base+4].copy_from_slice(&glyph_id.to_le_bytes());}}}Ok(bytes)}
fn write_atlas(patterns: &[[u8; 7]]) -> Vec<u8> {
    let mut pixels = vec![0u8; (ATLAS_WIDTH * ATLAS_HEIGHT) as usize];
    for (glyph, rows) in patterns.iter().enumerate() {
        for (row, bits) in rows.iter().enumerate() {
            for column in 0..5u32 {
                if bits & (1 << (4 - column)) != 0 {
                    let x = glyph as u32 * ATLAS_GLYPH_WIDTH + 1 + column;
                    let y = row as u32;
                    pixels[(y * ATLAS_WIDTH + x) as usize] = 255;
                }
            }
        }
    }
    pixels
}

fn digit_atlas_pixels() -> Vec<u8> {
    let patterns: [[u8; 7]; 10] = [
        [0b01110,0b10001,0b10011,0b10101,0b11001,0b10001,0b01110],
        [0b00100,0b01100,0b00100,0b00100,0b00100,0b00100,0b01110],
        [0b01110,0b10001,0b00001,0b00010,0b00100,0b01000,0b11111],
        [0b11110,0b00001,0b00001,0b01110,0b00001,0b00001,0b11110],
        [0b00010,0b00110,0b01010,0b10010,0b11111,0b00010,0b00010],
        [0b11111,0b10000,0b10000,0b11110,0b00001,0b00001,0b11110],
        [0b01110,0b10000,0b10000,0b11110,0b10001,0b10001,0b01110],
        [0b11111,0b00001,0b00010,0b00100,0b01000,0b01000,0b01000],
        [0b01110,0b10001,0b10001,0b01110,0b10001,0b10001,0b01110],
        [0b01110,0b10001,0b10001,0b01111,0b00001,0b00001,0b01110],
    ];
    write_atlas(&patterns)
}

fn ascii_atlas_pixels() -> Vec<u8> {
    let patterns: [[u8; 7]; 27] = [
        [0,0,0,0,0,0,0],
        [0b01110,0b10001,0b10001,0b11111,0b10001,0b10001,0b10001],
        [0b11110,0b10001,0b10001,0b11110,0b10001,0b10001,0b11110],
        [0b01110,0b10001,0b10000,0b10000,0b10000,0b10001,0b01110],
        [0b11110,0b10001,0b10001,0b10001,0b10001,0b10001,0b11110],
        [0b11111,0b10000,0b10000,0b11110,0b10000,0b10000,0b11111],
        [0b11111,0b10000,0b10000,0b11110,0b10000,0b10000,0b10000],
        [0b01110,0b10001,0b10000,0b10111,0b10001,0b10001,0b01110],
        [0b10001,0b10001,0b10001,0b11111,0b10001,0b10001,0b10001],
        [0b01110,0b00100,0b00100,0b00100,0b00100,0b00100,0b01110],
        [0b00001,0b00001,0b00001,0b00001,0b10001,0b10001,0b01110],
        [0b10001,0b10010,0b10100,0b11000,0b10100,0b10010,0b10001],
        [0b10000,0b10000,0b10000,0b10000,0b10000,0b10000,0b11111],
        [0b10001,0b11011,0b10101,0b10101,0b10001,0b10001,0b10001],
        [0b10001,0b11001,0b10101,0b10011,0b10001,0b10001,0b10001],
        [0b01110,0b10001,0b10001,0b10001,0b10001,0b10001,0b01110],
        [0b11110,0b10001,0b10001,0b11110,0b10000,0b10000,0b10000],
        [0b01110,0b10001,0b10001,0b10001,0b10101,0b10010,0b01101],
        [0b11110,0b10001,0b10001,0b11110,0b10100,0b10010,0b10001],
        [0b01111,0b10000,0b10000,0b01110,0b00001,0b00001,0b11110],
        [0b11111,0b00100,0b00100,0b00100,0b00100,0b00100,0b00100],
        [0b10001,0b10001,0b10001,0b10001,0b10001,0b10001,0b01110],
        [0b10001,0b10001,0b10001,0b10001,0b10001,0b01010,0b00100],
        [0b10001,0b10001,0b10001,0b10101,0b10101,0b10101,0b01010],
        [0b10001,0b10001,0b01010,0b00100,0b01010,0b10001,0b10001],
        [0b10001,0b10001,0b01010,0b00100,0b00100,0b00100,0b00100],
        [0b11111,0b00001,0b00010,0b00100,0b01000,0b10000,0b11111],
    ];
    write_atlas(&patterns)
}

fn main() -> Result<()> {
    let mut scene_path = "../out/registry-match.scene.json".to_string();
    let mut benchmark_report = None;
    let mut fusion_benchmark_report = None;
    let mut replay_matrix_report = None;
    let mut calibration_manifest_output = None;
    let mut freshness_registry = None;
    let mut freshness_manifest = None;
    let mut freshness_replay = None;
    let mut freshness_report = None;
    let mut freshness_threshold = 0.50f64;
    let mut freshness_minimum_samples = 5usize;
    let mut warmup_iterations = 5usize;
    let mut sample_iterations = 25usize;
    let mut data_register_patch: Option<(String, usize, String)> = None;
    let mut data_update_batch: Option<(String, String)> = None;
    let mut inject_list_release: Option<(String, usize)> = None;
    let mut inject_row_activate: Option<String> = None;
    let mut inject_log_append: Option<String> = None;
    let mut args = std::env::args().skip(1);
    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--benchmark-report" => benchmark_report = Some(args.next().context("--benchmark-report requires an output path")?),
            "--fusion-benchmark-report" => fusion_benchmark_report = Some(args.next().context("--fusion-benchmark-report requires an output path")?),
            "--replay-matrix" => replay_matrix_report = Some(args.next().context("--replay-matrix requires an output path")?),
            "--calibration-manifest" => calibration_manifest_output = Some(args.next().context("--calibration-manifest requires an output path")?),
            "--freshness-registry" => freshness_registry = Some(args.next().context("--freshness-registry requires a registry path")?),
            "--freshness-manifest" => freshness_manifest = Some(args.next().context("--freshness-manifest requires a manifest path")?),
            "--freshness-replay" => freshness_replay = Some(args.next().context("--freshness-replay requires a replay report path")?),
            "--freshness-report" => freshness_report = Some(args.next().context("--freshness-report requires an output path")?),
            "--freshness-threshold" => freshness_threshold = args.next().context("--freshness-threshold requires a fraction")?.parse().context("parse --freshness-threshold")?,
            "--freshness-min-samples" => freshness_minimum_samples = args.next().context("--freshness-min-samples requires an integer")?.parse().context("parse --freshness-min-samples")?,
            "--warmup" => warmup_iterations = args.next().context("--warmup requires an integer")?.parse().context("parse --warmup")?,
            "--samples" => sample_iterations = args.next().context("--samples requires an integer")?.parse().context("parse --samples")?,
            "--data-register-patch" => {
                let list = args.next().context("--data-register-patch requires list id, logical index, and uppercase value")?;
                let index = args.next().context("--data-register-patch requires logical index")?.parse().context("parse --data-register-patch index")?;
                let value = args.next().context("--data-register-patch requires uppercase value")?;
                data_register_patch = Some((list, index, value));
            }
            "--data-update-batch" => {
                let list = args.next().context("--data-update-batch requires list id and index=value records")?;
                let records = args.next().context("--data-update-batch requires comma-separated index=value records")?;
                data_update_batch = Some((list, records));
            }
            "--inject-list-release" => {
                let list = args.next().context("--inject-list-release requires list id and visible logical row")?;
                let logical = args.next().context("--inject-list-release requires logical row")?.parse().context("parse --inject-list-release logical row")?;
                inject_list_release = Some((list, logical));
            }
            "--inject-row-activate" => {
                inject_row_activate = Some(args.next().context("--inject-row-activate requires list id; use --inject-list-release first to establish selection")?);
            }
            "--inject-log-append" => {
                inject_log_append = Some(args.next().context("--inject-log-append requires compiler log-browser id")?);
            }
            _ => scene_path = argument,
        }
    }
    anyhow::ensure!([benchmark_report.is_some(), fusion_benchmark_report.is_some(), replay_matrix_report.is_some()].iter().filter(|selected| **selected).count() <= 1,
                    "choose at most one of --benchmark-report, --fusion-benchmark-report, or --replay-matrix");
    anyhow::ensure!(freshness_threshold >= 0.0 && freshness_threshold.is_finite(), "--freshness-threshold must be finite and non-negative");
    let freshness_requested = freshness_registry.is_some() || freshness_manifest.is_some() || freshness_replay.is_some() || freshness_report.is_some();
    if freshness_requested {
        let registry = freshness_registry.context("freshness gate requires --freshness-registry")?;
        let manifest = freshness_manifest.context("freshness gate requires --freshness-manifest")?;
        let replay = freshness_replay.context("freshness gate requires --freshness-replay")?;
        let report = freshness_report.context("freshness gate requires --freshness-report")?;
        write_freshness_diagnostic(&manifest, &registry, &scene_path, &replay, &report, freshness_threshold, freshness_minimum_samples)?;
        return Ok(());
    }
    anyhow::ensure!(calibration_manifest_output.is_none() || replay_matrix_report.is_some(), "--calibration-manifest requires --replay-matrix");
    let scene_text = fs::read_to_string(&scene_path).context("read compiled Scene")?;
    let scene_fingerprint_fnv1a64 = fnv1a64_hex(scene_text.as_bytes());
    let scene: Scene = serde_json::from_str(&scene_text)?;
    let mut builder = EventLoopBuilder::new();
    builder.with_x11();
    let event_loop = builder.build().context("create X11 event loop")?;
    compiler_abi_contracts(&scene)?;
    let visual_canvas = compiler_visual_language_plan(&scene)?;
    let window = Arc::new(WindowBuilder::new().with_title("Noir Glyph Atlas host")
        .with_inner_size(PhysicalSize::new(visual_canvas.width, visual_canvas.height)).build(&event_loop).context("create window")?);
    let scene_dir = Path::new(&scene_path).parent().unwrap_or_else(|| Path::new(".")).to_path_buf();
    let mut host = pollster::block_on(Host::new(window.clone(), scene, scene_dir, scene_fingerprint_fnv1a64)).context("initialize host")?;
    println!("noir-winit-host: {} quad instances, {} glyph placement(s), {} packet(s), profile={}",
             host.instances.len(), host.scene.glyph_placement_plan.len(), host.scene.glyph_draw_packets.len(),
             host.scene.render_schedules.first().map(|schedule| schedule.profile_id.as_str()).unwrap_or("none"));
    if let Some((list, index, value)) = data_register_patch.as_ref() { host.patch_compact_data_register(list, *index, value)?; }
    if let Some(log_browser) = inject_log_append.as_deref() { host.execute_log_browser_append(log_browser)?; }
    if let Some((list, logical)) = inject_list_release.as_ref() { host.inject_list_release(list, *logical)?; }
    if let Some(list) = inject_row_activate.as_deref() { host.inject_row_activate(list)?; }
    if let Some((list, records)) = data_update_batch.as_ref() {
        let updates = records.split(',').map(|record| {
            let (index, value) = record.split_once('=').context("data-update-batch record must use index=UPPERCASE_TEXT")?;
            Ok((index.parse::<usize>().context("parse data-update-batch index")?, value.to_string()))
        }).collect::<Result<Vec<_>>>()?;
        host.apply_compact_data_update_batch(list, &updates)?;
    }
    if let Some(report_path) = benchmark_report {
        host.run_benchmark_matrix(&report_path)?;
        return Ok(());
    }
    if let Some(report_path) = fusion_benchmark_report {
        host.run_fusion_benchmark(&report_path)?;
        return Ok(());
    }
    if let Some(report_path) = replay_matrix_report {
        host.run_replay_matrix(&report_path, warmup_iterations, sample_iterations)?;
        if let Some(manifest_path) = calibration_manifest_output {
            host.write_calibration_manifest(&report_path, &manifest_path)?;
        }
        return Ok(());
    }
    event_loop.run(move |event, target| {
        target.set_control_flow(ControlFlow::Wait);
        match event {
            Event::WindowEvent { window_id, event } if window_id == host.window.id() => match event {
                WindowEvent::CloseRequested => target.exit(),
                WindowEvent::Resized(size) => { host.resize(size); host.window.request_redraw(); }
                WindowEvent::CursorMoved { position, .. } => {
                    host.cursor = [position.x as f32 * host.canvas_width as f32 / host.size.width.max(1) as f32,
                                   position.y as f32 * host.canvas_height as f32 / host.size.height.max(1) as f32];
                    if !host.update_scrollbar_drag() {
                        if !host.set_list_hover_from_cursor() { host.set_hover(host.hit_test(host.cursor)); }
                    }
                    host.window.request_redraw();
                }
                WindowEvent::MouseInput { state: ElementState::Pressed, button: MouseButton::Left, .. } => {
                    if !host.begin_scrollbar_drag() { host.pointer_down(); }
                    host.window.request_redraw();
                }
                WindowEvent::MouseInput { state: ElementState::Released, button: MouseButton::Left, .. } => {
                    if !host.end_scrollbar_drag() {
                        if host.select_list_from_cursor() { host.activate_selected_list_row(); }
                        else { host.pointer_up(); }
                    }
                    host.window.request_redraw();
                }
                WindowEvent::MouseWheel { delta, .. } => {
                    let direction = match delta {
                        winit::event::MouseScrollDelta::LineDelta(_, y) => if y < 0.0 { 1 } else if y > 0.0 { -1 } else { 0 },
                        winit::event::MouseScrollDelta::PixelDelta(position) => if position.y < 0.0 { 1 } else if position.y > 0.0 { -1 } else { 0 },
                    };
                    host.scroll_virtual_list(direction);
                    host.window.request_redraw();
                }
                WindowEvent::ModifiersChanged(modifiers) => {
                    host.modifiers = modifiers.state();
                }
                WindowEvent::KeyboardInput { event, .. }
                    if event.state == ElementState::Pressed && matches!(event.logical_key, Key::Named(NamedKey::Tab)) => {
                    if !host.modal_focus_tab(host.modifiers.shift_key()) { host.focus_tab(host.modifiers.shift_key()); }
                    host.window.request_redraw();
                }
                WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed && matches!(event.logical_key, Key::Named(NamedKey::ArrowUp)) => {
                    host.navigate_list_selection(-1); host.window.request_redraw();
                }
                WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed && matches!(event.logical_key, Key::Named(NamedKey::ArrowDown)) => {
                    host.navigate_list_selection(1); host.window.request_redraw();
                }
                WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed && matches!(event.logical_key, Key::Named(NamedKey::PageUp)) => {
                    host.execute_list_navigation(ListNavigationKey::PageUp); host.window.request_redraw();
                }
                WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed && matches!(event.logical_key, Key::Named(NamedKey::PageDown)) => {
                    host.execute_list_navigation(ListNavigationKey::PageDown); host.window.request_redraw();
                }
                WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed && matches!(event.logical_key, Key::Named(NamedKey::Home)) => {
                    host.execute_list_navigation(ListNavigationKey::Home); host.window.request_redraw();
                }
                WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed && matches!(event.logical_key, Key::Named(NamedKey::End)) => {
                    host.execute_list_navigation(ListNavigationKey::End); host.window.request_redraw();
                }
                WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed => {
                    let ascii_upper = host.focus.as_ref().zip(host.keyboard.as_ref())
                        .map(|(focus, map)| map.fields[focus.current_slot].charset == "ascii-upper").unwrap_or(false);
                    if let Some(key_index) = keyboard_key_index(&event.logical_key, ascii_upper) {
                        host.keyboard_transition(key_index);
                        host.window.request_redraw();
                    } else if matches!(event.logical_key, Key::Named(NamedKey::Enter)) {
                        if !host.modal_focus_activate() && !host.activate_selected_list_row() { host.keyboard_command(KeyboardCommandKey::Enter); }
                        host.window.request_redraw();
                    } else if matches!(event.logical_key, Key::Named(NamedKey::Escape)) {
                        if !host.dismiss_active_overlay_with_escape() {
                            host.keyboard_command(KeyboardCommandKey::Escape);
                        }
                        host.window.request_redraw();
                    }
                }
                WindowEvent::RedrawRequested => if let Err(error) = host.present() { eprintln!("present error: {error:#}"); },
                _ => {}
            },
            Event::AboutToWait => {
                let blink = host.blink_tick();
                let motion = host.tick_release_motion();
                if blink || motion { host.window.request_redraw(); }
            },
            _ => {}
        }
    })?;
    Ok(())
}
