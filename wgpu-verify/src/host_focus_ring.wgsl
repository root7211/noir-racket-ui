struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) color: vec4<f32>,
  @location(1) local: vec2<f32>,
  @location(2) @interpolate(flat) ring_index: u32,
};

// One immutable entry per preallocated focus ring:
// [outer_radius_px, outline_thickness_px, outer_width_px, outer_height_px].
@group(0) @binding(0)
var<storage, read> focus_ring_meta: array<vec4<f32>>;

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
  out.ring_index = instance_index;
  return out;
}

fn rounded_box_sdf(point: vec2<f32>, half_size: vec2<f32>, radius: f32) -> f32 {
  let q = abs(point) - (half_size - vec2<f32>(radius));
  return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let data = focus_ring_meta[in.ring_index];
  if (data.x <= 0.0 || data.y <= 0.0 || in.color.a <= 0.0) {
    return vec4<f32>(0.0);
  }

  let outer_size = vec2<f32>(data.z, data.w);
  let half_size = outer_size * 0.5;
  let point = (in.local - vec2<f32>(0.5)) * outer_size;
  let outer_distance = rounded_box_sdf(point, half_size, data.x);

  // The compiler supplies geometry already expanded by its fixed halo. The outline
  // therefore occupies the outer 2px of this ring quad rather than filling it.
  let inner_half = max(half_size - vec2<f32>(data.y), vec2<f32>(0.0));
  let inner_radius = max(data.x - data.y, 0.0);
  let inner_distance = rounded_box_sdf(point, inner_half, inner_radius);
  let aa = max(fwidth(outer_distance), 0.5);
  let outer_coverage = 1.0 - smoothstep(-aa, aa, outer_distance);
  let inner_coverage = 1.0 - smoothstep(-aa, aa, inner_distance);
  let coverage = outer_coverage * (1.0 - inner_coverage);
  return vec4<f32>(in.color.rgb, in.color.a * coverage);
}
