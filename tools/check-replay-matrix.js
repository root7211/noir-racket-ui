#!/usr/bin/env node
'use strict';

const fs = require('fs');
const reportPath = process.argv[2];
if (!reportPath) throw new Error('usage: check-replay-matrix.js REPORT.json');
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const equal = (actual, expected, label) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
};
const truthy = (value, label) => { if (!value) throw new Error(`${label}: expected truthy value`); };
const validStats = (stats, samples, label) => {
  truthy(stats && stats.sample_count === samples, `${label}: sample count`);
  for (const key of ['min_ns', 'median_ns', 'p95_ns', 'max_ns', 'mean_ns']) {
    truthy(Number.isFinite(stats[key]) && stats[key] >= 0, `${label}: ${key}`);
  }
  truthy(stats.min_ns <= stats.median_ns && stats.median_ns <= stats.p95_ns && stats.p95_ns <= stats.max_ns,
         `${label}: percentile ordering`);
};

equal(report.schema, 'noir-wgpu-replay-matrix-v2', 'schema');
equal(report.renderer, 'full-redraw / packet-aware / action-aware / coalesced / compiler-selected', 'renderer');
truthy(report.timestamp_query_supported, 'timestamp_query_supported');
truthy(report.timestamp_period_ns > 0, 'timestamp_period_ns');
truthy(report.warmup_iterations >= 0, 'warmup_iterations');
truthy(report.sample_iterations > 0, 'sample_iterations');
equal(report.rows.length, 15, 'row count');

const expected = {
  'coalesced-activate-advance-progress-button': {
    'full-redraw': [1, 2, 31, 28], 'packet-aware': [6, 2, 6, 28],
    'action-aware': [1, 0, 0, 4], 'coalesced': [2, 0, 0, 28], 'compiler-selected': [2, 0, 0, 28],
  },
  'coalesced-activate-refresh-fps-button': {
    'full-redraw': [1, 2, 31, 36], 'packet-aware': [6, 2, 6, 36],
    'action-aware': [1, 1, 3, 12], 'coalesced': [2, 1, 3, 36], 'compiler-selected': [2, 1, 3, 36],
  },
  'coalesced-activate-refresh-latency-button': {
    'full-redraw': [1, 2, 31, 36], 'packet-aware': [6, 2, 6, 36],
    'action-aware': [1, 1, 3, 12], 'coalesced': [2, 1, 3, 36], 'compiler-selected': [2, 1, 3, 36],
  },
};
for (const row of report.rows) {
  const target = expected[row.workload_id]?.[row.mode];
  truthy(target, `unexpected row ${row.workload_id}/${row.mode}`);
  equal(row.warmup_iterations, report.warmup_iterations, `${row.workload_id}/${row.mode}: warmup`);
  equal(row.sample_iterations, report.sample_iterations, `${row.workload_id}/${row.mode}: samples`);
  equal([row.submitted_tile_count, row.submitted_glyph_draw_count, row.submitted_glyph_instance_count, row.expected_write_bytes],
        target, `${row.workload_id}/${row.mode}: work metrics`);
  validStats(row.cpu_event_to_submit_ns, report.sample_iterations, `${row.workload_id}/${row.mode}: CPU`);
  validStats(row.gpu_elapsed_ns, report.sample_iterations, `${row.workload_id}/${row.mode}: GPU`);
  if (row.mode === 'compiler-selected') {
    const consistency = row.compiler_selected;
    truthy(consistency && consistency.self_consistent, `${row.workload_id}: compiler-selected consistency`);
    equal(consistency.compiler_strategy_id, 'coalesced', `${row.workload_id}: compiler strategy`);
    equal(consistency.proof_profile_id, 'noir-vulkan-gpu-matrix-v1', `${row.workload_id}: proof profile`);
    equal(consistency.proof_winner, 'coalesced', `${row.workload_id}: proof winner`);
    equal(consistency.actual_executor, 'coalesced', `${row.workload_id}: actual executor`);
    const expectedMask = row.workload_id.includes('fps') ? '0x0000000000000009'
      : row.workload_id.includes('latency') ? '0x0000000000000012'
      : '0x0000000000000024';
    equal(consistency.expected_tile_mask_hex, expectedMask, `${row.workload_id}: expected tile mask`);
    equal(consistency.observed_tile_mask_hex, expectedMask, `${row.workload_id}: observed tile mask`);
    equal(consistency.expected_winner_write_bytes, row.expected_write_bytes, `${row.workload_id}: expected winner bytes`);
    equal(consistency.observed_winner_write_bytes, row.expected_write_bytes, `${row.workload_id}: observed winner bytes`);
    equal(consistency.observed_tile_count, row.submitted_tile_count, `${row.workload_id}: observed tile count`);
    equal(consistency.observed_glyph_instance_count, row.submitted_glyph_instance_count, `${row.workload_id}: observed glyph instances`);
  } else {
    equal(row.compiler_selected, undefined, `${row.workload_id}/${row.mode}: no compiler-selected payload`);
  }
}
console.log('noir replay matrix JSON oracle passed');
