const addon = require('../build/index.node');

test('sumArray([1, 2, 3]) returns 6', () => {
  expect(addon.sumArray([1, 2, 3])).toBe(6);
});

test('sumArray([]) returns 0', () => {
  expect(addon.sumArray([])).toBe(0);
});

test('sumArray([1.5, 2.5]) returns 4', () => {
  expect(addon.sumArray([1.5, 2.5])).toBe(4);
});

test('sumArray() with no args throws', () => {
  expect(() => addon.sumArray()).toThrow();
});

test('sumArray({}) throws (plain object, not array)', () => {
  expect(() => addon.sumArray({})).toThrow();
});

test('sumArray("hello") throws (wrong type)', () => {
  expect(() => addon.sumArray("hello")).toThrow();
});
