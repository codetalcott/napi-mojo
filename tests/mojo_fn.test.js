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

// uppercase — mojo_fn with string type (Step 3)
test('uppercase("hello") returns "HELLO"', () => {
  expect(addon.uppercase('hello')).toBe('HELLO');
});

test('uppercase("Hello World") returns "HELLO WORLD"', () => {
  expect(addon.uppercase('Hello World')).toBe('HELLO WORLD');
});

test('uppercase("") returns ""', () => {
  expect(addon.uppercase('')).toBe('');
});

test('uppercase throws TypeError on non-string', () => {
  try {
    addon.uppercase(42);
    fail('should have thrown');
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});

// sumArray — mojo_fn with number[] type (Step 3)
test('sumArray([1,2,3]) returns 6', () => {
  expect(addon.sumArrayPure([1, 2, 3])).toBe(6);
});

test('sumArray([]) returns 0', () => {
  expect(addon.sumArrayPure([])).toBe(0);
});

test('sumArray([1.5, 2.5]) returns 4', () => {
  expect(addon.sumArrayPure([1.5, 2.5])).toBe(4);
});

test('sumArray throws TypeError on non-array', () => {
  try {
    addon.sumArrayPure(42);
    fail('should have thrown');
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});
