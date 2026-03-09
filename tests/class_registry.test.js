'use strict';
const addon = require('../build/index.node');

describe('newCounterFromRegistry / ClassRegistry (Phase 25b)', () => {
  test('returns a Counter instance', () => {
    const c = addon.newCounterFromRegistry(5);
    expect(c).toBeInstanceOf(addon.Counter);
  });

  test('value is set to constructor argument', () => {
    const c = addon.newCounterFromRegistry(5);
    expect(c.value).toBe(5);
  });

  test('returns Counter with value 0', () => {
    const c = addon.newCounterFromRegistry(0);
    expect(c.value).toBe(0);
  });

  test('returns Counter with large value', () => {
    const c = addon.newCounterFromRegistry(999);
    expect(c.value).toBe(999);
  });

  test('instance methods work on result', () => {
    const c = addon.newCounterFromRegistry(3);
    c.increment();
    expect(c.value).toBe(4);
  });
});
