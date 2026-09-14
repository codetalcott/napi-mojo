const addon = require('../build/index.node');

test('createCallback() returns a function', () => {
  const fn = addon.createCallback();
  expect(typeof fn).toBe('function');
});

test('createCallback()() returns "hello from callback"', () => {
  const fn = addon.createCallback();
  expect(fn()).toBe('hello from callback');
});

test('createAdder(5) returns a function', () => {
  const add5 = addon.createAdder(5);
  expect(typeof add5).toBe('function');
});

test('createAdder(5)(3) returns 8', () => {
  const add5 = addon.createAdder(5);
  expect(add5(3)).toBe(8);
});

test('createAdder(0)(0) returns 0', () => {
  const add0 = addon.createAdder(0);
  expect(add0(0)).toBe(0);
});

test('createAdder(n, counter) captures n the same way', () => {
  // The optional counter only makes the capture's finalizer observable
  // (tests/finalizer_gc.test.js); it must not change what the adder does.
  const add7 = addon.createAdder(7, new ArrayBuffer(8));
  expect(add7(3)).toBe(10);
  expect(add7(-7)).toBe(0);
});

test('an adder can be called many times — nothing is freed on the call path', () => {
  const add1 = addon.createAdder(1, new ArrayBuffer(8));
  let total = 0;
  for (let i = 0; i < 1000; i++) total = add1(total);
  expect(total).toBe(1000);
});
