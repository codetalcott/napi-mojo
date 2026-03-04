const addon = require('../build/index.node');

// Counter.isCounter tests
test('Counter.isCounter is a function', () => {
  expect(typeof addon.Counter.isCounter).toBe('function');
});

test('Counter.isCounter(new Counter(0)) returns true', () => {
  const c = new addon.Counter(0);
  expect(addon.Counter.isCounter(c)).toBe(true);
});

test('Counter.isCounter({}) returns false', () => {
  expect(addon.Counter.isCounter({})).toBe(false);
});

test('Counter.isCounter(42) returns false', () => {
  expect(addon.Counter.isCounter(42)).toBe(false);
});

test('Counter.isCounter(null) returns false', () => {
  expect(addon.Counter.isCounter(null)).toBe(false);
});

test('Counter.isCounter(undefined) returns false', () => {
  expect(addon.Counter.isCounter(undefined)).toBe(false);
});

test('Counter.isCounter("hello") returns false', () => {
  expect(addon.Counter.isCounter('hello')).toBe(false);
});

// Counter.fromValue tests
test('Counter.fromValue is a function', () => {
  expect(typeof addon.Counter.fromValue).toBe('function');
});

test('Counter.fromValue(5) creates Counter with value 5', () => {
  const c = addon.Counter.fromValue(5);
  expect(c.value).toBe(5);
});

test('Counter.fromValue(0) creates Counter with value 0', () => {
  const c = addon.Counter.fromValue(0);
  expect(c.value).toBe(0);
});

test('Counter.fromValue result is instanceof Counter', () => {
  const c = addon.Counter.fromValue(10);
  expect(addon.Counter.isCounter(c)).toBe(true);
});

test('Counter.fromValue result has working methods', () => {
  const c = addon.Counter.fromValue(3);
  c.increment();
  expect(c.value).toBe(4);
  c.reset();
  expect(c.value).toBe(3);
});

test('Counter.fromValue with non-number throws', () => {
  expect(() => addon.Counter.fromValue('hello')).toThrow();
});

// Static methods are not on instances
test('counter instance does not have isCounter', () => {
  const c = new addon.Counter(0);
  expect(c.isCounter).toBeUndefined();
});

test('counter instance does not have fromValue', () => {
  const c = new addon.Counter(0);
  expect(c.fromValue).toBeUndefined();
});
