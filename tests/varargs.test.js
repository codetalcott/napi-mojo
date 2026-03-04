const addon = require('../build/index.node');

test('sumArgs(1, 2, 3) returns 6', () => {
  expect(addon.sumArgs(1, 2, 3)).toBe(6);
});

test('sumArgs(10) returns 10', () => {
  expect(addon.sumArgs(10)).toBe(10);
});

test('sumArgs() with no args returns 0', () => {
  expect(addon.sumArgs()).toBe(0);
});

test('sumArgs(1, 2, 3, 4, 5) returns 15', () => {
  expect(addon.sumArgs(1, 2, 3, 4, 5)).toBe(15);
});

test('sumArgs with non-number arg throws', () => {
  expect(() => addon.sumArgs(1, 'two', 3)).toThrow();
});
