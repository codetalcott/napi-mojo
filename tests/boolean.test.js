const addon = require('../build/index.node');

test('isPositive(1) returns true', () => {
  expect(addon.isPositive(1)).toBe(true);
});

test('isPositive(-1) returns false', () => {
  expect(addon.isPositive(-1)).toBe(false);
});

test('isPositive(0) returns false', () => {
  expect(addon.isPositive(0)).toBe(false);
});

test('isPositive("hello") throws', () => {
  expect(() => addon.isPositive('hello')).toThrow();
});
