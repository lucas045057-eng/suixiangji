import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  addTransaction,
  createSeedState,
  deriveMetrics,
  generateInsights,
  getMonthlySeries,
  parseNaturalLanguage,
} from '../outputs/wealthmate/app.js';

test('seed state exposes a useful current-month financial snapshot', () => {
  const state = createSeedState();
  const metrics = deriveMetrics(state, '2026-09');

  assert.equal(metrics.income, 18500);
  assert.equal(metrics.expense, 5288);
  assert.equal(metrics.savings, 13212);
  assert.equal(metrics.savingsRate, 0.714);
  assert.equal(metrics.assets, 16320);
  assert.equal(metrics.liabilities, 2180);
  assert.equal(metrics.netWorth, 14140);
  assert.equal(metrics.budgetUsage.find((item) => item.category === '餐饮').percent, 0.64);
});

test('natural language expense becomes a reviewable classified draft', () => {
  const draft = parseNaturalLanguage('今天中午外卖 32 元，支付宝', new Date('2026-09-01T10:00:00+08:00'));

  assert.deepEqual(draft, {
    amount: 32,
    type: 'expense',
    category: '餐饮',
    accountId: 'alipay',
    date: '2026-09-01',
    note: '今天中午外卖 32 元，支付宝',
    confidence: 0.98,
  });
});

test('adding a transaction returns a new state and updates derived balances', () => {
  const state = createSeedState();
  const nextState = addTransaction(state, {
    amount: 20,
    type: 'expense',
    category: '交通',
    accountId: 'alipay',
    date: '2026-09-01',
    note: '地铁',
  });

  assert.equal(state.transactions.length + 1, nextState.transactions.length);
  assert.equal(state.transactions.length, 12);
  assert.equal(deriveMetrics(nextState, '2026-09').expense, 5308);
  assert.equal(deriveMetrics(nextState, '2026-09').assets, 16300);
});

test('monthly series ends at the live net worth and keeps the five-month trend', () => {
  const state = createSeedState();
  const series = getMonthlySeries(state, 5);

  assert.deepEqual(series.labels, ['5月', '6月', '7月', '8月', '9月']);
  assert.deepEqual(series.values, [9120, 10480, 11630, 13120, 14140]);
});

test('insights prioritize an over-budget category and explain the emergency fund runway', () => {
  const state = createSeedState();
  const insights = generateInsights(deriveMetrics(state, '2026-09'), state);

  assert.equal(insights[0].severity, 'warning');
  assert.match(insights[0].title, /住房/);
  assert.ok(insights.some((insight) => insight.title.includes('应急金')));
});

test('web package exposes install metadata and service worker registration', async () => {
  const manifest = JSON.parse(await readFile(new URL('../outputs/wealthmate/manifest.webmanifest', import.meta.url), 'utf8'));
  const html = await readFile(new URL('../outputs/wealthmate/index.html', import.meta.url), 'utf8');
  const app = await readFile(new URL('../outputs/wealthmate/app.js', import.meta.url), 'utf8');

  assert.equal(manifest.name, '随想记');
  assert.equal(manifest.display, 'standalone');
  assert.match(html, /rel="manifest"/);
  assert.match(app, /serviceWorker\.register\(['"]\.\/service-worker\.js/);
});

test('soft-deleted transactions stay in local data but leave live metrics and lists', () => {
  const state = createSeedState();
  const deleted = { ...state.transactions[0], deletedAt: '2026-09-12T10:00:00+08:00' };
  const nextState = { ...state, transactions: [deleted, ...state.transactions.slice(1)] };
  const metrics = deriveMetrics(nextState, '2026-09');

  assert.equal(nextState.transactions.length, 12);
  assert.equal(metrics.income, 0);
  assert.equal(metrics.assets, 16320 - 18500);
});
