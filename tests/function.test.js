const addon = require('../build/index.node');

test('callFunction(x => x + 1, 5) returns 6', () => {
  expect(addon.callFunction(x => x + 1, 5)).toBe(6);
});

test('callFunction(s => s.toUpperCase(), "hello") returns "HELLO"', () => {
  expect(addon.callFunction(s => s.toUpperCase(), "hello")).toBe("HELLO");
});

test('callFunction(42, 1) throws (not a function)', () => {
  expect(() => addon.callFunction(42, 1)).toThrow();
});

test('callFunction() with no args throws', () => {
  expect(() => addon.callFunction()).toThrow();
});
