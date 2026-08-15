#!/usr/bin/env node
'use strict';

const fs = require('fs');
const [strictPath, permissivePath] = process.argv.slice(2);
if (!strictPath || !permissivePath) {
  throw new Error('usage: check-profile-admission.js STRICT_FRESH.scene.json PERMISSIVE_STALE.scene.json');
}
const load = path => JSON.parse(fs.readFileSync(path, 'utf8'));
const equal = (actual, expected, label) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
};
const activateBatches = scene => scene.frame_coalesced_batches.filter(batch => batch.id.startsWith('coalesced-activate-'));
const strict = activateBatches(load(strictPath));
const permissive = activateBatches(load(permissivePath));
equal(strict.length, 3, 'strict activate batch count');
equal(permissive.length, 3, 'permissive activate batch count');
for (const batch of strict) {
  equal(batch.strategy_id, 'coalesced', `${batch.id}: strict strategy`);
  equal(batch.selection_proof.mode, 'profile-guided', `${batch.id}: strict proof mode`);
  equal(batch.selection_proof.profile_id, 'noir-vulkan-gpu-matrix-v1', `${batch.id}: strict profile`);
  equal(batch.selection_proof.semantic_group, 'complete-activate-v1', `${batch.id}: strict semantic group`);
  equal(batch.selection_proof.winner, 'coalesced', `${batch.id}: strict winner`);
  equal(Object.keys(batch.candidate_costs).sort(), ['coalesced', 'full-redraw', 'packet-aware'], `${batch.id}: strict candidates`);
  if ('action-aware' in batch.candidate_costs) throw new Error(`${batch.id}: action-aware must not enter complete activate candidates`);
}
for (const batch of permissive) {
  equal(batch.strategy_id, 'coalesced', `${batch.id}: permissive strategy`);
  equal(batch.selection_proof.mode, 'profile-unavailable', `${batch.id}: permissive proof mode`);
  equal(batch.selection_proof.reason, 'freshness-not-fresh', `${batch.id}: permissive reason`);
  equal(batch.selection_proof.admission_policy, 'permissive', `${batch.id}: permissive policy`);
  equal(batch.selection_proof.freshness_status, 'stale', `${batch.id}: permissive freshness status`);
  equal(batch.candidate_costs, {coalesced: 0}, `${batch.id}: permissive conservative costs`);
}
console.log('noir Racket Profile Admission scene oracle passed');
