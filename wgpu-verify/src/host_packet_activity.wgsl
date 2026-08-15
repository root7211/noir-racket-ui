// Portable GPU-driven packet activity prepass.
// One compiler-emitted subgroup packet maps to one 32-invocation workgroup.
// The ABI is shared with the optional subgroupBallot implementation; this variant
// uses a deterministic workgroup reduction so it runs on wgpu 0.20 fallback adapters.

struct PacketDescriptor {
  first_placement: u32,
  lane_count: u32,
  active_lane_mask: u32,
  dynamic: u32,
};

struct DrawIndirect {
  vertex_count: u32,
  instance_count: u32,
  first_vertex: u32,
  first_instance: u32,
};

@group(0) @binding(0) var<storage, read> glyph_words: array<u32>;
@group(0) @binding(1) var<storage, read> packets: array<PacketDescriptor>;
@group(0) @binding(2) var<storage, read_write> activity_masks: array<u32>;
@group(0) @binding(3) var<storage, read_write> indirect_commands: array<DrawIndirect>;
// Uniform avoids a fifth storage-buffer binding on downlevel/llvmpipe hardware.
// `lanes[0..7]` encodes 32 compiler-proved packet IDs.
struct PacketWorklist { count: u32, _pad0: vec3<u32>, lanes: array<vec4<u32>, 8> };
@group(0) @binding(4) var<uniform> packet_worklist: PacketWorklist;

var<workgroup> visible: array<u32, 32>;

@compute @workgroup_size(32)
fn packet_activity(@builtin(workgroup_id) group: vec3<u32>,
                   @builtin(local_invocation_id) local_id: vec3<u32>) {
  let lane = local_id.x;
  let packet_index = packet_worklist.lanes[group.x / 4u][group.x % 4u];
  let packet = packets[packet_index];
  let in_range = lane < packet.lane_count;
  let glyph_word_offset = (packet.first_placement + lane) * 8u;
  let glyph_id = select(0x00010000u, glyph_words[glyph_word_offset], in_range);
  // Static packets are always active. Dynamic page-1 space is compiler-defined blank.
  visible[lane] = select(0u, 1u, in_range && (packet.dynamic == 0u || glyph_id != 0x00010000u));
  workgroupBarrier();
  if (lane == 0u) {
    var any_visible = 0u;
    var i = 0u;
    loop {
      if (i >= packet.lane_count) { break; }
      any_visible = any_visible | visible[i];
      i = i + 1u;
    }
    let packet_is_active = any_visible != 0u;
    activity_masks[packet_index] = select(0u, packet.active_lane_mask, packet_is_active);
    indirect_commands[packet_index] = DrawIndirect(6u, select(0u, packet.lane_count, packet_is_active), 0u, packet.first_placement);
  }
}
