const ATLAS_GLYPH_WIDTH: f32 = 6.0;
const ATLAS_WIDTH: f32 = 162.0;
const ATLAS_HEIGHT: f32 = 8.0;

@group(0) @binding(0) var<storage, read> glyph_words: array<u32>;
@group(0) @binding(1) var glyph_atlas: texture_2d_array<f32>;
@group(0) @binding(2) var atlas_sampler: sampler;

struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) color: vec4<f32>,
  @location(2) @interpolate(flat) atlas_page: i32,
};

@vertex
fn vs_main(
  @builtin(vertex_index) vertex_index: u32,
  @location(1) pos: vec2<f32>,
  @location(2) size: vec2<f32>,
  @location(3) color: vec4<f32>,
  @location(4) glyph_word_offset: u32,
  @location(5) glyph_enabled: u32,
  @location(6) glyph_count: u32,
) -> VsOut {
  var corners = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0),
  );
  var out: VsOut;
  if (glyph_enabled == 0u || glyph_count == 0u) {
    out.position = vec4<f32>(2.0, 2.0, 0.0, 1.0);
    out.uv = vec2<f32>(0.0, 0.0);
    out.color = vec4<f32>(0.0);
    out.atlas_page = 0;
    return out;
  }
  let glyph_index = vertex_index / 6u;
  let corner = corners[vertex_index % 6u];
  let cell_width = size.x * 0.76 / f32(glyph_count);
  let glyph_width = cell_width * 0.76;
  let glyph_height = size.y * 0.72;
  let glyph_pos = vec2<f32>(
    pos.x + size.x * 0.12 + f32(glyph_index) * cell_width,
    pos.y + size.y * 0.19,
  );
  let glyph_id = glyph_words[glyph_word_offset + glyph_index * 8u];
  let atlas_page = glyph_id >> 16u;
  let atlas_glyph_index = glyph_id & 0xffffu;
  let atlas_px = vec2<f32>(f32(atlas_glyph_index) * ATLAS_GLYPH_WIDTH + 1.0, 1.0) + corner * vec2<f32>(5.0, 7.0);
  out.position = vec4<f32>(glyph_pos + corner * vec2<f32>(glyph_width, glyph_height), 0.0, 1.0);
  // Atlas uploads begin at the top row; glyph geometry uses an NDC lower-left origin.
  out.uv = (vec2<f32>(f32(atlas_glyph_index) * ATLAS_GLYPH_WIDTH + 1.0, 1.0)
            + vec2<f32>(corner.x, 1.0 - corner.y) * vec2<f32>(5.0, 7.0))
           / vec2<f32>(ATLAS_WIDTH, ATLAS_HEIGHT);
  out.color = vec4<f32>(0.97, 0.86, 0.34, 1.0);
  out.atlas_page = i32(atlas_page);
  return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let coverage = textureSample(glyph_atlas, atlas_sampler, in.uv, in.atlas_page).r;
  return vec4<f32>(in.color.rgb, in.color.a * coverage);
}
