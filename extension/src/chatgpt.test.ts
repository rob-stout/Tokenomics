/**
 * Regression tests for the ChatGPT local counter math.
 *
 * Run via `npm run test`. Tests are bundled by esbuild into dist-test/ and
 * executed with `node --test`. We bundle so module resolution works the same
 * as the production build (relative imports without explicit `.ts`).
 */

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
  deriveSnapshot,
  type ChatGPTPlan,
  pruneEvents,
  type ChatGPTMessageEvent,
} from './chatgpt';

const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;
const NOW = 1_700_000_000_000;

function evt(offsetMs: number, model: string | null = 'gpt-5.5'): ChatGPTMessageEvent {
  return { ts: NOW - offsetMs, model };
}

// ── deriveSnapshot ───────────────────────────────────────────

/** deriveSnapshot for a plan that has a counter; fails the test if it doesn't. */
function derive(events: ChatGPTMessageEvent[], plan: ChatGPTPlan) {
  const snap = deriveSnapshot(events, plan, NOW);
  assert.ok(snap, `expected a counter snapshot for ${plan}`);
  return snap;
}

test('deriveSnapshot returns chatgpt provider with estimated flag', () => {
  // The fallback counter routes to the ChatGPT pool (was mistakenly 'codex',
  // which collided with the real Codex CLI pool on the Mac side).
  const snap = derive([], 'plus');
  assert.equal(snap.provider, 'chatgpt');
  assert.equal(snap.estimated, true);
});

test('Free and Go have unlimited chat: no estimated meter', () => {
  const events = [evt(HOUR), evt(2 * HOUR)];
  assert.equal(deriveSnapshot(events, 'free', NOW), null);
  assert.equal(deriveSnapshot(events, 'go', NOW), null);
});

test('unknown / enterprise / edu plans have no counter table', () => {
  assert.equal(deriveSnapshot([evt(HOUR)], 'unknown', NOW), null);
  assert.equal(deriveSnapshot([evt(HOUR)], 'enterprise', NOW), null);
  assert.equal(deriveSnapshot([evt(HOUR)], 'edu', NOW), null);
});

test('empty events on plus plan → 0 / 160', () => {
  const snap = derive([], 'plus');
  assert.equal(snap.shortWindow.utilization, 0);
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^0 of 160 msgs/);
});

test('16 events in last 3h on plus → 10% utilization', () => {
  const events = Array.from({ length: 16 }, (_, i) => evt(HOUR + i * 60_000));
  const snap = derive(events, 'plus');
  assert.equal(snap.shortWindow.utilization, 10);
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^16 of 160 msgs/);
});

test('events older than the short window are ignored', () => {
  const events = [
    evt(4 * HOUR),         // outside 3h window
    evt(7 * HOUR),         // outside
    evt(HOUR),             // inside
  ];
  const snap = derive(events, 'plus');
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^1 of 160 msgs/);
});

test('utilization clamps at 100', () => {
  const events = Array.from({ length: 500 }, (_, i) => evt(i * 1000));
  const snap = derive(events, 'plus');
  assert.equal(snap.shortWindow.utilization, 100);
});

test('reset = oldestInWindow.ts + windowMs', () => {
  const oldestOffset = 2 * HOUR; // 2h ago
  const events = [evt(oldestOffset), evt(HOUR)];
  const snap = derive(events, 'plus');
  const resetMs = new Date(snap.shortWindow.resetsAt).getTime();
  // Oldest event was 2h ago, 3h window → resets in 1h.
  assert.equal(resetMs, NOW - oldestOffset + 3 * HOUR);
});

test('reset = now + windowMs when no events in window', () => {
  const snap = derive([], 'plus');
  const resetMs = new Date(snap.shortWindow.resetsAt).getTime();
  assert.equal(resetMs, NOW + 3 * HOUR);
});

test('plus plan exposes longWindow with thinking-msg label', () => {
  const snap = derive([], 'plus');
  assert.ok(snap.longWindow);
  assert.equal(snap.longWindow!.label, 'Weekly Thinking');
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^0 of 3000 thinking msgs/);
});

test('plus plan: non-thinking models do NOT count in longWindow', () => {
  const events = [evt(DAY, 'gpt-5.5'), evt(2 * DAY, 'gpt-5.5')];
  const snap = derive(events, 'plus');
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^0 of 3000 thinking msgs/);
});

test('plus plan: thinking models DO count in longWindow', () => {
  const events = [
    evt(DAY, 'gpt-5-thinking'),
    evt(2 * DAY, 'o3-pro'),
    evt(3 * DAY, 'gpt-5.5'),       // not thinking
    evt(4 * DAY, 'o1-mini-preview'), // matches startsWith('o1')
  ];
  const snap = derive(events, 'plus');
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^3 of 3000 thinking msgs/);
});

test('plus plan: thinking events older than 7d are dropped from longWindow', () => {
  const events = [
    evt(6 * DAY, 'gpt-5-thinking'),  // inside week
    evt(8 * DAY, 'gpt-5-thinking'),  // outside week
  ];
  const snap = derive(events, 'plus');
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^1 of 3000 thinking msgs/);
});

test('pro plan uses 5000-msg short cap and 15000 weekly', () => {
  const snap = derive([], 'pro');
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^0 of 5000 msgs/);
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^0 of 15000 thinking msgs/);
});

test('team plan mirrors plus quotas', () => {
  const snap = derive([], 'team');
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^0 of 160 msgs/);
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^0 of 3000 thinking msgs/);
});

test('plan label maps cleanly', () => {
  assert.equal(derive([], 'plus').planLabel, 'Plus');
  assert.equal(derive([], 'prolite').planLabel, 'Pro 100');
  assert.equal(derive([], 'pro').planLabel, 'Pro 200');
  assert.equal(derive([], 'promax').planLabel, 'Pro 500');
  assert.equal(derive([], 'team').planLabel, 'Team');
  assert.equal(derive([], 'business').planLabel, 'Business');
});

test('prolite and promax reuse the Pro counter table', () => {
  assert.match(derive([], 'prolite').shortWindow.sublabelOverride ?? '', /^0 of 5000 msgs/);
  assert.match(derive([], 'promax').shortWindow.sublabelOverride ?? '', /^0 of 5000 msgs/);
});

test('sublabel includes a reset hint when there is one', () => {
  const snap = derive([evt(HOUR)], 'plus');
  assert.match(snap.shortWindow.sublabelOverride ?? '', /resets in/);
});

// ── pruneEvents ──────────────────────────────────────────────

test('pruneEvents keeps events at the 7d boundary', () => {
  const events = [
    evt(7 * DAY - 1),  // just inside
    evt(7 * DAY + 1),  // just outside
  ];
  const kept = pruneEvents(events, NOW);
  assert.equal(kept.length, 1);
  assert.equal(kept[0].ts, NOW - (7 * DAY - 1));
});

test('pruneEvents on empty input is empty', () => {
  assert.deepEqual(pruneEvents([], NOW), []);
});

test('pruneEvents preserves order', () => {
  const events = [evt(DAY), evt(2 * DAY), evt(3 * DAY)];
  const kept = pruneEvents(events, NOW);
  assert.deepEqual(
    kept.map((e) => e.ts),
    [NOW - DAY, NOW - 2 * DAY, NOW - 3 * DAY],
  );
});
