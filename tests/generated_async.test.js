'use strict';
const addon = require('../build/index.node');

describe('asyncSum — generated async function (Phase 31)', () => {
  test('returns a Promise', () => {
    const result = addon.asyncSum(3, 4);
    expect(typeof result.then).toBe('function');
  });

  test('asyncSum(3, 4) resolves to 7', async () => {
    expect(await addon.asyncSum(3, 4)).toBe(7);
  });

  test('asyncSum(0, 0) resolves to 0', async () => {
    expect(await addon.asyncSum(0, 0)).toBe(0);
  });

  test('asyncSum(-5, 3) resolves to -2', async () => {
    expect(await addon.asyncSum(-5, 3)).toBe(-2);
  });

  test('multiple concurrent calls resolve independently', async () => {
    const [a, b, c] = await Promise.all([
      addon.asyncSum(1, 2),
      addon.asyncSum(10, 20),
      addon.asyncSum(100, 200),
    ]);
    expect(a).toBe(3);
    expect(b).toBe(30);
    expect(c).toBe(300);
  });
});
