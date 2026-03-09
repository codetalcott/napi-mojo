const addon = require('../build/index.node');

// square(x) and clamp(val, lo, hi) are generated via mojo_fn key in exports.toml

test('square(4) returns 16', () => {
  expect(addon.square(4)).toBe(16);
});

test('square(0) returns 0', () => {
  expect(addon.square(0)).toBe(0);
});

test('square(-3) returns 9', () => {
  expect(addon.square(-3)).toBe(9);
});

test('clamp(5, 0, 10) returns 5', () => {
  expect(addon.clamp(5, 0, 10)).toBe(5);
});

test('clamp(-1, 0, 10) returns 0 (clamped to lo)', () => {
  expect(addon.clamp(-1, 0, 10)).toBe(0);
});

test('clamp(15, 0, 10) returns 10 (clamped to hi)', () => {
  expect(addon.clamp(15, 0, 10)).toBe(10);
});

test('square throws TypeError on non-number', () => {
  try {
    addon.square('x');
    fail('should have thrown');
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});
