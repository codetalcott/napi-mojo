const addon = require('../build/index.node');

describe('asyncTriple (AsyncWork framework)', () => {
  test('asyncTriple(3) resolves to 9', async () => {
    const result = await addon.asyncTriple(3);
    expect(result).toBe(9);
  });

  test('asyncTriple(0) resolves to 0', async () => {
    const result = await addon.asyncTriple(0);
    expect(result).toBe(0);
  });

  test('asyncTriple(-4) resolves to -12', async () => {
    const result = await addon.asyncTriple(-4);
    expect(result).toBe(-12);
  });

  test('asyncTriple returns a promise', () => {
    const p = addon.asyncTriple(1);
    expect(typeof p.then).toBe('function');
    return p;
  });

  test('multiple concurrent asyncTriple calls', async () => {
    const results = await Promise.all([
      addon.asyncTriple(1),
      addon.asyncTriple(2),
      addon.asyncTriple(10),
    ]);
    expect(results).toEqual([3, 6, 30]);
  });
});
