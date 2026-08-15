struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) color: vec4<f32>,
};

@vertex
fn vs_main(
  @location(0) corner: vec2<f32>,
  @location(1) pos: vec2<f32>,
  @location(2) size: vec2<f32>,
  @location(3) color: vec4<f32>,
) -> VsOut {
  var out: VsOut;
  out.position = vec4<f32>(pos + corner * size, 0.0, 1.0);
  out.color = color;
  return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  return in.color;
}
