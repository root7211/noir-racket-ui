const ATLAS_GLYPH_WIDTH: f32 = 6.0;
const ATLAS_GLYPH_HEIGHT: f32 = 8.0;
const ATLAS_WIDTH: f32 = 60.0;
const ATLAS_HEIGHT: f32 = 8.0;

struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) color: vec4<f32>,
  @location(1) uv: vec2<f32>,
  @interpolate(flat) @location(2) text_run_enabled: u32,
};

// 每个 glyph cell 固定 32 bytes，即 8 个 u32。第一个 word 是 atlas digit index。
@group(0) @binding(0)
var<storage, read> glyph_words: array<u32>;
@group(0) @binding(1)
var digit_atlas: texture_2d<f32>;
@group(0) @binding(2)
var atlas_sampler: sampler;

@vertex
fn vs_main(
  @builtin(vertex_index) vertex_index: u32,
  @location(0) pos: vec2<f32>,
  @location(1) size: vec2<f32>,
  @location(2) color: vec4<f32>,
  @location(3) glyph_word_offset: u32,
  @location(4) glyph_enabled: u32,
  @location(5) glyph_count: u32,
) -> VsOut {
  var corners = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0),
  );
  var output: VsOut;
  output.color = color;
  output.uv = vec2<f32>(0.0, 0.0);
  output.text_run_enabled = glyph_enabled;

  if (glyph_enabled == 0u) {
    // 静态节点仍是原来的 1 个实例 quad；多余 vertex 放到 clip 外。
    if (vertex_index >= 6u) {
      output.position = vec4<f32>(2.0, 2.0, 0.0, 1.0);
      output.color = vec4<f32>(0.0);
      return output;
    }
    let unit = corners[vertex_index];
    output.position = vec4<f32>(pos + unit * size, 0.0, 1.0);
    return output;
  }

  let total_vertices = glyph_count * 6u;
  if (vertex_index >= total_vertices) {
    output.position = vec4<f32>(2.0, 2.0, 0.0, 1.0);
    output.color = vec4<f32>(0.0);
    return output;
  }

  let glyph_index = vertex_index / 6u;
  let corner_index = vertex_index % 6u;
  let unit = corners[corner_index];
  let glyph_width = size.x / f32(glyph_count) * 0.58;
  let glyph_height = size.y * 0.62;
  let glyph_x = pos.x + size.x * 0.12 + f32(glyph_index) * (size.x / f32(glyph_count));
  let glyph_y = pos.y + size.y * 0.19;
  output.position = vec4<f32>(vec2<f32>(glyph_x, glyph_y) + unit * vec2<f32>(glyph_width, glyph_height), 0.0, 1.0);

  let digit = glyph_words[glyph_word_offset + glyph_index * 8u];
  let atlas_px = vec2<f32>(f32(digit) * ATLAS_GLYPH_WIDTH + 1.0, 1.0) + unit * vec2<f32>(3.0, 5.0);
  output.uv = atlas_px / vec2<f32>(ATLAS_WIDTH, ATLAS_HEIGHT);
  output.color = vec4<f32>(0.97, 0.86, 0.34, 1.0);
  return output;
}

@fragment
fn fs_main(input: VsOut) -> @location(0) vec4<f32> {
  if (input.text_run_enabled == 1u) {
    let coverage = textureSample(digit_atlas, atlas_sampler, input.uv).r;
    return vec4<f32>(input.color.rgb, input.color.a * coverage);
  }
  return input.color;
}
