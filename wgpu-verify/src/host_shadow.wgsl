struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) color: vec4<f32>,
  @location(1) local: vec2<f32>,
  @location(2) @interpolate(flat) layer_index: u32,
};

// One immutable entry per shadow draw instance:
// [source_radius_px, blur_px, source_width_px, source_height_px].
@group(0) @binding(0)
var<storage, read> shadow_surface_meta: array<vec4<f32>>;

@vertex
fn vs_main(
  @location(0) corner: vec2<f32>,
  @location(1) pos: vec2<f32>,
  @location(2) size: vec2<f32>,
  @location(3) color: vec4<f32>,
  @builtin(instance_index) instance_index: u32,
) -> VsOut {
  var out: VsOut;
  out.position = vec4<f32>(pos + corner * size, 0.0, 1.0);
  out.color = color;
  out.local = corner;
  out.layer_index = instance_index;
  return out;
}

fn rounded_box_sdf(point: vec2<f32>, half_size: vec2<f32>, radius: f32) -> f32 {
  let q = abs(point) - (half_size - vec2<f32>(radius));
  return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let data = shadow_surface_meta[in.layer_index];
  if (data.y <= 0.0 || in.color.a <= 0.0) {
    return vec4<f32>(0.0);
  }
  let outer_size = vec2<f32>(data.z + 2.0 * data.y, data.w + 2.0 * data.y);
  let point = (in.local - vec2<f32>(0.5)) * outer_size;
  let distance = rounded_box_sdf(point, vec2<f32>(data.z, data.w) * 0.5, data.x);
  // The interior is intentionally fully opaque; the source surface is drawn later
  // and occludes it. Only the compiler-fixed exterior blur band contributes.
  let aa = max(fwidth(distance), 0.5);
  let coverage = 1.0 - smoothstep(-aa, data.y, distance);
  return vec4<f32>(in.color.rgb, in.color.a * coverage);
}
