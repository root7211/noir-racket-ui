struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) color: vec4<f32>,
  @location(1) local: vec2<f32>,
  @location(2) @interpolate(flat) instance_index: u32,
};

// One vec4 per frozen QuadInstance slot: radius_px, aa_width_px, width_px, height_px.
// A zero radius is the backward-compatible hard rectangle path.
@group(0) @binding(0)
var<storage, read> rounded_surface_meta: array<vec4<f32>>;

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
  out.instance_index = instance_index;
  return out;
}

fn rounded_box_sdf(point: vec2<f32>, half_size: vec2<f32>, radius: f32) -> f32 {
  let q = abs(point) - (half_size - vec2<f32>(radius));
  return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let surface_data = rounded_surface_meta[in.instance_index];
  if (surface_data.x <= 0.0 || in.color.a <= 0.0) {
    return in.color;
  }
  let half_size = vec2<f32>(surface_data.z, surface_data.w) * 0.5;
  let point = (in.local - vec2<f32>(0.5)) * vec2<f32>(surface_data.z, surface_data.w);
  let distance = rounded_box_sdf(point, half_size, surface_data.x);
  let aa = max(surface_data.y, 0.5);
  let coverage = 1.0 - smoothstep(-aa, aa, distance);
  return vec4<f32>(in.color.rgb, in.color.a * coverage);
}
