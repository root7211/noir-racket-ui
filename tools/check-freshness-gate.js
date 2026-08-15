#!/usr/bin/env node
'use strict';

const fs = require('fs');
const [manifestPath, freshPath, stalePath, inconclusivePath] = process.argv.slice(2);
if (!manifestPath || !freshPath || !stalePath || !inconclusivePath) {
  throw new Error('usage: check-freshness-gate.js MANIFEST.json FRESH.json STALE.json INCONCLUSIVE.json');
}
const load = path => JSON.parse(fs.readFileSync(path, 'utf8'));
const equal = (actual, expected, label) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
};
const truthy = (value, label) => { if (!value) throw new Error(`${label}: expected truthy value`); };
const manifest = load(manifestPath);
equal(manifest.schema, 'noir-calibration-manifest-v1', 'manifest schema');
equal(manifest.profile_id, 'noir-vulkan-gpu-matrix-v1', 'manifest profile');
equal(manifest.compiler_selected.length, 3, 'manifest case count');
truthy(manifest.scene_fingerprint_fnv1a64.startsWith('fnv1a64:'), 'scene fingerprint');
truthy(manifest.replay_report_fingerprint_fnv1a64.startsWith('fnv1a64:'), 'report fingerprint');
for (const entry of manifest.compiler_selected) {
  equal(entry.strategy_id, 'coalesced', `${entry.batch_id}: fixed strategy`);
  truthy(entry.gpu_median_ns >= 0 && entry.gpu_p95_ns >= entry.gpu_median_ns, `${entry.batch_id}: timestamp stats`);
}
const reports = [
  [load(freshPath), 'fresh'],
  [load(stalePath), 'stale'],
  [load(inconclusivePath), 'inconclusive'],
];
for (const [report, expectedStatus] of reports) {
  equal(report.schema, 'noir-profile-freshness-v1', `${expectedStatus}: schema`);
  equal(report.status, expectedStatus, `${expectedStatus}: status`);
  equal(report.policy, 'diagnostic-only; runtime strategy_id is immutable', `${expectedStatus}: policy`);
  equal(report.comparisons.length, 3, `${expectedStatus}: comparison count`);
  for (const item of report.comparisons) {
    equal(item.strategy_id, 'coalesced', `${expectedStatus}/${item.batch_id}: strategy unchanged`);
    truthy(item.work_contract_matches, `${expectedStatus}/${item.batch_id}: work contract`);
    truthy(Number.isFinite(item.median_relative_drift) && item.median_relative_drift >= 0,
           `${expectedStatus}/${item.batch_id}: median drift`);
    truthy(Number.isFinite(item.p95_relative_drift) && item.p95_relative_drift >= 0,
           `${expectedStatus}/${item.batch_id}: p95 drift`);
  }
}
const stale = reports[1][0];
truthy(stale.comparisons.some(item => item.median_relative_drift > 0 || item.p95_relative_drift > 0),
       'stale report must show non-zero replay/profile drift');
const inconclusive = reports[2][0];
truthy(inconclusive.checks.some(check => check.name === 'minimum-samples' && !check.passed),
       'inconclusive report must identify insufficient samples');
console.log('noir calibration manifest and freshness gate oracle passed');
