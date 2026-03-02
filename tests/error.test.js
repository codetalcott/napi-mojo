const addon = require('../build/index.node');

test('greet() with no args throws', () => {
  expect(() => addon.greet()).toThrow();
});

test('greet(123) throws (number is not a string)', () => {
  expect(() => addon.greet(123)).toThrow();
});

test('add("a", "b") throws (strings are not numbers)', () => {
  expect(() => addon.add('a', 'b')).toThrow();
});

test('add(1) throws (too few args)', () => {
  expect(() => addon.add(1)).toThrow();
});

test('isPositive() throws (no args)', () => {
  expect(() => addon.isPositive()).toThrow();
});
