// Optional feature-gated compute prepass for Noir's compiler-emitted width-32 packet plan.
// Compile this module only when the wgpu adapter exposes Features::SUBGROUP.
// The normal host renderer remains semantically identical through fixed packet draw fallback.

enable subgroups;

struct SubgroupPacket {
  first_placement: u32,
  lane_count: u32,
  active_lane_mask: u32,
  dynamic: u32,
};

@group(0) @binding(0) var<storage, read> packets: array<SubgroupPacket>;
@group(0) @binding(1) var<storage, read> glyph_words: array<u32>;
// One u32 per compiler packet. 0 means every dynamic lane is page-1-space / transparent;
// otherwise this is the compiler active_lane_mask. Static packets are always emitted active.
@group(0) @binding(2) var<storage, read_write> active_masks: array<u32>;

@compute @workgroup_size(32)
fn packet_activity(@builtin(workgroup_id) group: vec3<u32>,
                   @builtin(subgroup_invocation_id) lane: u32) {
  let packet_index = group.x;
  let packet = packets[packet_index];
  let lane_in_range = lane < packet.lane_count;
  let glyph_word = (packet.first_placement + lane) * 8u;
  let glyph_id = select(0x00010000u, glyph_words[glyph_word], lane_in_range);
  // Page-1 space is the compiler's deterministic blank glyph for ASCII fields.
  let lane_visible = lane_in_range && (packet.dynamic == 0u || glyph_id != 0x00010000u);
  let any_visible = subgroupAny(lane_visible);
  if (lane == 0u) {
    active_masks[packet_index] = select(0u, packet.active_lane_mask, any_visible);
  }
}
