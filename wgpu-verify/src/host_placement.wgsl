const ATLAS_GLYPH_WIDTH: f32 = 6.0;
const ATLAS_WIDTH: f32 = 162.0;
const ATLAS_HEIGHT: f32 = 8.0;

// glyph_words 的每个 cell 为 8 个 u32；动态路径只读取其首word的compiler
// admitted glyph ID。page 2 始终静态；page 3 的UV来自immutable 37-entry table。
@group(0) @binding(0) var<storage, read> glyph_words: array<u32>;
@group(0) @binding(1) var legacy_glyph_atlas: texture_2d_array<f32>;
@group(0) @binding(2) var legacy_atlas_sampler: sampler;
@group(0) @binding(3) var fontc_glyph_atlas: texture_2d<f32>;
@group(0) @binding(4) var fontc_atlas_sampler: sampler;
@group(0) @binding(5) var<storage, read> tabular_body_uvs: array<vec4<f32>>;
@group(0) @binding(6) var tabular_body_atlas: texture_2d<f32>;
@group(0) @binding(7) var tabular_body_sampler: sampler;

struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) color: vec4<f32>,
  @location(2) @interpolate(flat) atlas_page: i32,
};

@vertex
fn vs_main(
  @location(0) corner: vec2<f32>,
  @location(1) pos: vec2<f32>,
  @location(2) size: vec2<f32>,
  @location(3) compiler_atlas_uv: vec4<f32>,
  @location(4) glyph_word_offset: u32,
  @location(5) compiler_atlas_page: u32,
  @location(6) dynamic: u32,
) -> VsOut {
  var atlas_uv = compiler_atlas_uv;
  var atlas_page = compiler_atlas_page;

  // A dynamic plan may select legacy page 0/1 or page 3. The Rust startup proof
  // guarantees page 3 IDs are dense <37 and that no page 2 placement is dynamic.
  if (dynamic != 0u) {
    let glyph_id = glyph_words[glyph_word_offset];
    let glyph_index = glyph_id & 0xffffu;
    atlas_page = glyph_id >> 16u;
    if (atlas_page == 3u) {
      atlas_uv = tabular_body_uvs[glyph_index];
    } else {
      atlas_uv = vec4<f32>(
        (f32(glyph_index) * ATLAS_GLYPH_WIDTH + 1.0) / ATLAS_WIDTH,
        1.0 / ATLAS_HEIGHT,
        5.0 / ATLAS_WIDTH,
        7.0 / ATLAS_HEIGHT,
      );
    }
  }

  var out: VsOut;
  out.position = vec4<f32>(pos + corner * size, 0.0, 1.0);
  // Placement positions are NDC lower-left quads while texture uploads use a top-row origin.
  out.uv = atlas_uv.xy + vec2<f32>(corner.x, 1.0 - corner.y) * atlas_uv.zw;
  out.color = vec4<f32>(0.90, 0.95, 1.0, 1.0);
  out.atlas_page = i32(atlas_page);
  return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  // Page selection is compiler-owned. There is no runtime font lookup, fallback,
  // shaping, UV computation, or mutable bind-group selection.
  var coverage: f32;
  if (in.atlas_page == 2) {
    coverage = textureSample(fontc_glyph_atlas, fontc_atlas_sampler, in.uv).r;
  } else if (in.atlas_page == 3) {
    coverage = textureSample(tabular_body_atlas, tabular_body_sampler, in.uv).r;
  } else {
    coverage = textureSample(legacy_glyph_atlas, legacy_atlas_sampler, in.uv, in.atlas_page).r;
  }
  return vec4<f32>(in.color.rgb, in.color.a * coverage);
}
