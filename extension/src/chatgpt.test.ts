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

test('deriveSnapshot returns chatgpt provider with estimated flag', () => {
  // The fallback counter routes to the ChatGPT pool (was mistakenly 'codex',
  // which collided with the real Codex CLI pool on the Mac side).
  const snap = deriveSnapshot([], 'free', NOW);
  assert.equal(snap.provider, 'chatgpt');
  assert.equal(snap.estimated, true);
});

test('empty events on free plan → 0 / 10, longWindow null', () => {
  const snap = deriveSnapshot([], 'free', NOW);
  assert.equal(snap.shortWindow.utilization, 0);
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^0 of 10 msgs/);
  assert.equal(snap.longWindow, null);
});

test('5 events in last 5h on free → 50% utilization', () => {
  const events = [evt(HOUR), evt(2 * HOUR), evt(3 * HOUR), evt(4 * HOUR), evt(4.5 * HOUR)];
  const snap = deriveSnapshot(events, 'free', NOW);
  assert.equal(snap.shortWindow.utilization, 50);
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^5 of 10 msgs/);
});

test('events older than the short window are ignored', () => {
  const events = [
    evt(6 * HOUR),         // outside 5h window
    evt(7 * HOUR),         // outside
    evt(HOUR),             // inside
  ];
  const snap = deriveSnapshot(events, 'free', NOW);
  assert.equal(snap.shortWindow.utilization, 10);
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^1 of 10 msgs/);
});

test('utilization clamps at 100', () => {
  const events = Array.from({ length: 50 }, (_, i) => evt(i * 60 * 1000));
  const snap = deriveSnapshot(events, 'free', NOW);
  assert.equal(snap.shortWindow.utilization, 100);
});

test('reset = oldestInWindow.ts + windowMs', () => {
  const oldestOffset = 4 * HOUR; // 4h ago
  const events = [evt(oldestOffset), evt(HOUR)];
  const snap = deriveSnapshot(events, 'free', NOW);
  const resetMs = new Date(snap.shortWindow.resetsAt).getTime();
  // Oldest event was 4h ago, 5h window → resets in 1h.
  assert.equal(resetMs, NOW - oldestOffset + 5 * HOUR);
});

test('reset = now + windowMs when no events in window', () => {
  const snap = deriveSnapshot([], 'free', NOW);
  const resetMs = new Date(snap.shortWindow.resetsAt).getTime();
  assert.equal(resetMs, NOW + 5 * HOUR);
});

test('unknown plan falls back to free quota', () => {
  const events = [evt(HOUR)];
  const snap = deriveSnapshot(events, 'unknown', NOW);
  assert.equal(snap.shortWindow.utilization, 10); // 1/10 = 10%
  assert.equal(snap.longWindow, null);
});

test('plus plan exposes longWindow with thinking-msg label', () => {
  const snap = deriveSnapshot([], 'plus', NOW);
  assert.ok(snap.longWindow);
  assert.equal(snap.longWindow!.label, 'Weekly Thinking');
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^0 of 3000 thinking msgs/);
});

test('plus plan: non-thinking models do NOT count in longWindow', () => {
  const events = [evt(DAY, 'gpt-5.5'), evt(2 * DAY, 'gpt-5.5')];
  const snap = deriveSnapshot(events, 'plus', NOW);
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^0 of 3000 thinking msgs/);
});

test('plus plan: thinking models DO count in longWindow', () => {
  const events = [
    evt(DAY, 'gpt-5-thinking'),
    evt(2 * DAY, 'o3-pro'),
    evt(3 * DAY, 'gpt-5.5'),       // not thinking
    evt(4 * DAY, 'o1-mini-preview'), // matches startsWith('o1')
  ];
  const snap = deriveSnapshot(events, 'plus', NOW);
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^3 of 3000 thinking msgs/);
});

test('plus plan: thinking events older than 7d are dropped from longWindow', () => {
  const events = [
    evt(6 * DAY, 'gpt-5-thinking'),  // inside week
    evt(8 * DAY, 'gpt-5-thinking'),  // outside week
  ];
  const snap = deriveSnapshot(events, 'plus', NOW);
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^1 of 3000 thinking msgs/);
});

test('pro plan uses 5000-msg short cap and 15000 weekly', () => {
  const snap = deriveSnapshot([], 'pro', NOW);
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^0 of 5000 msgs/);
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^0 of 15000 thinking msgs/);
});

test('team plan mirrors plus quotas', () => {
  const snap = deriveSnapshot([], 'team', NOW);
  assert.match(snap.shortWindow.sublabelOverride ?? '', /^0 of 160 msgs/);
  assert.match(snap.longWindow!.sublabelOverride ?? '', /^0 of 3000 thinking msgs/);
});

test('plan label maps cleanly', () => {
  assert.equal(deriveSnapshot([], 'free', NOW).planLabel, 'Free');
  assert.equal(deriveSnapshot([], 'plus', NOW).planLabel, 'Plus');
  assert.equal(deriveSnapshot([], 'pro', NOW).planLabel, 'Pro');
  assert.equal(deriveSnapshot([], 'team', NOW).planLabel, 'Team');
  assert.equal(deriveSnapshot([], 'unknown', NOW).planLabel, '');
});

test('sublabel includes a reset hint when there is one', () => {
  const snap = deriveSnapshot([evt(HOUR)], 'free', NOW);
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
