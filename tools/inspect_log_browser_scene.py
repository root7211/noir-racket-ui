#!/usr/bin/env python3
"""Print only log-browser detail placement/range evidence from a compiled Scene JSON."""
import json
import sys

scene = json.load(open(sys.argv[1], encoding="utf-8"))
artifact = scene["log_browser_plans"][0]
detail = artifact["detail_node_id"]
placements = [p for p in scene["glyph_placement_plan"] if p["node"] == detail]
print("artifact_detail_tile_ids", artifact["detail_tile_ids"])
print("detail_slots", [p["slot"] for p in placements])
print("detail_offsets", [p["glyph_byte_offset"] for p in placements])
for schedule in scene["render_schedules"]:
    print("schedule", schedule["id"])
    for index, tile in enumerate(schedule["tiles"]):
        ranges = [(r["first_placement"], r["placement_count"], r["packet_id"]) for r in tile["glyph_packet_ranges"]]
        covered = [p["slot"] for p in placements if any(first <= p["slot"] < first + count for first, count, _ in ranges)]
        print("tile", index, "ranges", ranges, "detail_covered", covered)
