#!/usr/bin/env node
'use strict';

const fs = require('fs');
const reportPath = process.argv[2];
if (!reportPath) {
  throw new Error('usage: check-benchmark-report.js REPORT.json');
}
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
function equal(actual, expected, label) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}
function truthy(value, label) {
  if (!value) throw new Error(`${label}: expected truthy value`);
}

equal(report.schema, 'noir-wgpu-benchmark-v1', 'schema');
truthy(report.timestamp_query_supported, 'timestamp_query_supported');
truthy(report.timestamp_period_ns > 0, 'timestamp_period_ns');
equal(report.cases.length, 3, 'benchmark case count');

const byId = Object.fromEntries(report.cases.map((entry) => [entry.id, entry]));
const checks = [
  ['coalesced-activate-advance-progress-button', '0x0000000000000024', 3, 28, 2, 0, 0],
  ['coalesced-activate-refresh-fps-button', '0x0000000000000009', 5, 36, 2, 1, 3],
  ['coalesced-activate-refresh-latency-button', '0x0000000000000012', 5, 36, 2, 1, 3],
];
for (const [id, mask, writes, bytes, tiles, draws, instances] of checks) {
  const entry = byId[id];
  truthy(entry, `${id}: missing case`);
  equal(entry.expected_tile_mask_hex, mask, `${id}: expected mask`);
  equal(entry.observed_tile_mask_hex, mask, `${id}: observed mask`);
  equal(entry.expected_winner_write_count, writes, `${id}: winner write count`);
  equal(entry.expected_winner_write_bytes, bytes, `${id}: winner write bytes`);
  equal(entry.submitted_tile_count, tiles, `${id}: tile count`);
  equal(entry.submitted_glyph_draw_count, draws, `${id}: glyph draw count`);
  equal(entry.submitted_glyph_instance_count, instances, `${id}: glyph instance count`);
  truthy(entry.expectations_match, `${id}: compiler expectation check`);
  truthy(typeof entry.cpu_event_to_submit_ns === 'number' && entry.cpu_event_to_submit_ns > 0,
         `${id}: cpu_event_to_submit_ns`);
  truthy(typeof entry.gpu_elapsed_ns === 'number' && entry.gpu_elapsed_ns >= 0,
         `${id}: gpu_elapsed_ns`);
}
console.log('noir benchmark JSON oracle passed');
