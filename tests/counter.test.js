const addon = require('../build/index.node');

test('new Counter(0) creates instance with value 0', () => {
  const c = new addon.Counter(0);
  expect(c.value).toBe(0);
});

test('counter.increment() increases value by 1', () => {
  const c = new addon.Counter(0);
  c.increment();
  expect(c.value).toBe(1);
  c.increment();
  expect(c.value).toBe(2);
});

test('counter.value getter returns current value', () => {
  const c = new addon.Counter(5);
  expect(c.value).toBe(5);
});

test('counter.value = 10 setter works', () => {
  const c = new addon.Counter(0);
  c.value = 10;
  expect(c.value).toBe(10);
});

test('counter.reset() resets to initial value', () => {
  const c = new addon.Counter(3);
  c.increment();
  c.increment();
  expect(c.value).toBe(5);
  c.reset();
  expect(c.value).toBe(3);
});

test('multiple instances are independent', () => {
  const a = new addon.Counter(0);
  const b = new addon.Counter(100);
  a.increment();
  expect(a.value).toBe(1);
  expect(b.value).toBe(100);
});

test('Counter constructor without args throws', () => {
  expect(() => new addon.Counter()).toThrow();
});

test('Counter constructor with non-number throws', () => {
  expect(() => new addon.Counter('hello')).toThrow();
});

test('method on non-wrapped prototype object throws', () => {
  const fake = Object.create(addon.Counter.prototype);
  expect(() => fake.increment()).toThrow();
});
