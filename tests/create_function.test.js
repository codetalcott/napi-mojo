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
