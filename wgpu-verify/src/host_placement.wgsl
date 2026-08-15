const ATLAS_GLYPH_WIDTH: f32 = 6.0;
const ATLAS_WIDTH: f32 = 162.0;
const ATLAS_HEIGHT: f32 = 8.0;

// glyph_words 的每个 glyph cell 为 8 个 u32；Placement Plan 已将 word offset
// 固定为 cell 起始 word。静态 placement 的 dynamic=0，因此完全不读取此 buffer。
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

  // 动态数字只修改 glyph_id 的一个 u32。placement 的 NDC quad、UV 尺寸、clip/z/batch
  // 均不改变；这里仅将已写入的 glyph index 映射至同一 page 0 的 cell origin。
  if (dynamic != 0u) {
    let glyph_id = glyph_words[glyph_word_offset];
    let glyph_index = glyph_id & 0xffffu;
    atlas_page = glyph_id >> 16u;
    atlas_uv = vec4<f32>(
      (f32(glyph_index) * ATLAS_GLYPH_WIDTH + 1.0) / ATLAS_WIDTH,
      1.0 / ATLAS_HEIGHT,
      5.0 / ATLAS_WIDTH,
      7.0 / ATLAS_HEIGHT,
    );
  }

  var out: VsOut;
  out.position = vec4<f32>(pos + corner * size, 0.0, 1.0);
  // Placement positions are NDC lower-left quads while texture uploads use a top-row origin.
  // Preserve U and flip only V so glyphs remain left-to-right but no longer render upside down.
  out.uv = atlas_uv.xy + vec2<f32>(corner.x, 1.0 - corner.y) * atlas_uv.zw;
  // Cool near-white foreground keeps the 3×5 atlas legible on Noir's dark application surfaces.
  out.color = vec4<f32>(0.90, 0.95, 1.0, 1.0);
  out.atlas_page = i32(atlas_page);
  return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let coverage = textureSample(glyph_atlas, atlas_sampler, in.uv, in.atlas_page).r;
  return vec4<f32>(in.color.rgb, in.color.a * coverage);
}
