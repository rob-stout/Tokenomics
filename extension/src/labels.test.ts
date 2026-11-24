import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { resolveTextLabels } from './labels';

test('default (never set) shows logos', () => {
  assert.equal(resolveTextLabels(null, false), false);
});

test('user choice is respected in a normal build', () => {
  assert.equal(resolveTextLabels(true, false), true);
  assert.equal(resolveTextLabels(false, false), false);
});

test('text-labels build forces site names regardless of stored choice', () => {
  assert.equal(resolveTextLabels(null, true), true);
  assert.equal(resolveTextLabels(false, true), true);
});
