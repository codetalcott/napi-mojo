const addon = require('../build/index.node');

// --- addInts: Int32 addition ---

test('addInts(3, 4) returns 7', () => {
  expect(addon.addInts(3, 4)).toBe(7);
});

test('addInts(0, 0) returns 0', () => {
  expect(addon.addInts(0, 0)).toBe(0);
});

test('addInts(-100, 100) returns 0', () => {
  expect(addon.addInts(-100, 100)).toBe(0);
});

test('addInts(2147483647, 0) returns INT32_MAX', () => {
  expect(addon.addInts(2147483647, 0)).toBe(2147483647);
});

test('addInts("a", 1) throws on non-number', () => {
  expect(() => addon.addInts('a', 1)).toThrow();
});

test('addInts() with no args throws', () => {
  expect(() => addon.addInts()).toThrow();
});

// --- bitwiseOr: UInt32 bitwise OR ---

test('bitwiseOr(5, 3) returns 7', () => {
  expect(addon.bitwiseOr(5, 3)).toBe(7);
});

test('bitwiseOr(0xFF, 0x0F) returns 0xFF', () => {
  expect(addon.bitwiseOr(0xFF, 0x0F)).toBe(0xFF);
});

test('bitwiseOr(4294967295, 0) returns UINT32_MAX', () => {
  expect(addon.bitwiseOr(4294967295, 0)).toBe(4294967295);
});

test('bitwiseOr("a", 1) throws on non-number', () => {
  expect(() => addon.bitwiseOr('a', 1)).toThrow();
});

test('bitwiseOr() with no args throws', () => {
  expect(() => addon.bitwiseOr()).toThrow();
});
