const addon = require('../build/index.node');

test('addBigInts(1n, 2n) returns 3n', () => {
  expect(addon.addBigInts(1n, 2n)).toBe(3n);
});

test('addBigInts(0n, 0n) returns 0n', () => {
  expect(addon.addBigInts(0n, 0n)).toBe(0n);
});

test('addBigInts(-5n, 3n) returns -2n', () => {
  expect(addon.addBigInts(-5n, 3n)).toBe(-2n);
});

test('addBigInts result is typeof bigint', () => {
  const result = addon.addBigInts(1n, 1n);
  expect(typeof result).toBe('bigint');
});

test('addBigInts with large values works', () => {
  const a = BigInt(Number.MAX_SAFE_INTEGER);
  const b = 1n;
  expect(addon.addBigInts(a, b)).toBe(a + b);
});

test('addBigInts with non-bigint throws', () => {
  expect(() => addon.addBigInts(1, 2)).toThrow();
});

test('addBigInts with negative large values', () => {
  expect(addon.addBigInts(-100n, -200n)).toBe(-300n);
});
