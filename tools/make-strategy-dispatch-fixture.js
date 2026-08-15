#!/usr/bin/env node
'use strict';

const fs = require('fs');
const [input, output, strategy] = process.argv.slice(2);
if (!input || !output || !['full-redraw', 'packet-aware'].includes(strategy)) {
  throw new Error('usage: make-strategy-dispatch-fixture.js INPUT.json OUTPUT.json full-redraw|packet-aware');
}
const scene = JSON.parse(fs.readFileSync(input, 'utf8'));
for (const batch of scene.frame_coalesced_batches ?? []) {
  if (!batch.id.startsWith('coalesced-activate-')) continue;
  const costs = strategy === 'full-redraw'
    ? { 'full-redraw': 1, 'packet-aware': 2, coalesced: 3 }
    : { 'full-redraw': 3, 'packet-aware': 1, coalesced: 2 };
  batch.strategy_id = strategy;
  batch.candidate_costs = costs;
  batch.selection_proof = {
    mode: 'profile-guided',
    profile_id: `dispatcher-test-${strategy}`,
    semantic_group: 'complete-activate-v1',
    selection_metric: 'gpu_median_ns',
    source_batch: batch.id,
    winner: strategy,
    tie_break_order: ['full-redraw', 'packet-aware', 'coalesced'],
  };
}
fs.writeFileSync(output, JSON.stringify(scene, null, 2) + '\n');
console.log(`wrote dispatcher fixture ${output} with strategy=${strategy}`);
