#!/usr/bin/env node
'use strict';

const fs = require('fs');
const [bootstrapPath, strictPath, manifestPath, freshnessPath] = process.argv.slice(2);
if (!bootstrapPath || !strictPath || !manifestPath || !freshnessPath) {
  throw new Error('usage: check-build-attestation.js BOOTSTRAP.scene.json STRICT.scene.json MANIFEST.json FRESHNESS.json');
}
const load = path => JSON.parse(fs.readFileSync(path, 'utf8'));
const equal = (actual, expected, label) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
};
const bootstrap = load(bootstrapPath);
const strict = load(strictPath);
const manifest = load(manifestPath);
const freshness = load(freshnessPath);
for (const [name, scene] of [['bootstrap', bootstrap], ['strict', strict]]) {
  equal(scene.build_attestation.schema, 'noir-build-attestation-v1', `${name}: attestation schema`);
  equal(scene.build_attestation.compiler_abi, 'noir-racket-ui-abi-v2', `${name}: compiler ABI`);
  equal(scene.build_attestation.scene_json_abi, 'noir-scene-json-v2', `${name}: Scene ABI`);
  if (!scene.build_attestation.source_fingerprint_fnv1a64.startsWith('fnv1a64:')) {
    throw new Error(`${name}: source fingerprint is missing`);
  }
  if (!scene.build_attestation.canonical_input.builder_source.startsWith('fnv1a64:')) {
    throw new Error(`${name}: builder source was omitted from canonical input`);
  }
}
equal(bootstrap.build_attestation.source_fingerprint_fnv1a64,
      strict.build_attestation.source_fingerprint_fnv1a64,
      'bootstrap/strict source identity');
equal(manifest.source_fingerprint_fnv1a64,
      strict.build_attestation.source_fingerprint_fnv1a64,
      'manifest/strict source identity');
equal(freshness.status, 'fresh', 'freshness status');
const sourceCheck = freshness.checks.find(check => check.name === 'source-fingerprint');
const outputCheck = freshness.checks.find(check => check.name === 'scene-output-fingerprint-informational');
if (!sourceCheck || !sourceCheck.passed) throw new Error('freshness report did not pass source fingerprint check');
if (!outputCheck || !outputCheck.passed) throw new Error('freshness report lacks informational output Scene hash');
const activate = strict.frame_coalesced_batches.filter(batch => batch.id.startsWith('coalesced-activate-'));
equal(activate.length, 3, 'strict activate batch count');
for (const batch of activate) {
  equal(batch.selection_proof.mode, 'profile-guided', `${batch.id}: strict proof mode`);
  equal(batch.selection_proof.admission_policy, 'strict', `${batch.id}: strict automatic admission`);
  equal(batch.selection_proof.freshness_status, 'fresh', `${batch.id}: strict freshness`);
}
console.log(`Noir build attestation oracle passed: ${manifest.source_fingerprint_fnv1a64}`);
