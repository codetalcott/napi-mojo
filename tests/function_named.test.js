'use strict';
const addon = require('../build/index.node');

describe('createNamedFn / JsFunction.create_named (Phase 25a)', () => {
  test('returns a function', () => {
    const fn = addon.createNamedFn();
    expect(typeof fn).toBe('function');
  });

  test('function has name "myFn"', () => {
    const fn = addon.createNamedFn();
    expect(fn.name).toBe('myFn');
  });

  test('function has length 2', () => {
    const fn = addon.createNamedFn();
    expect(fn.length).toBe(2);
  });

  test('function is callable', () => {
    const fn = addon.createNamedFn();
    // inner_callback_fn just returns undefined — we just verify it doesn't throw
    expect(() => fn()).not.toThrow();
  });
});
