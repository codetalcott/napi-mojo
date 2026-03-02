const addon = require('../build/index.node');

test('add(2, 3) returns 5', () => {
  expect(addon.add(2, 3)).toBe(5);
});

test('add(0, 0) returns 0', () => {
  expect(addon.add(0, 0)).toBe(0);
});

test('add(-1.5, 2.5) returns 1', () => {
  expect(addon.add(-1.5, 2.5)).toBe(1);
});
