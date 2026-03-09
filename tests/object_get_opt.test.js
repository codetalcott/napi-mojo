'use strict';
const addon = require('../build/index.node');

describe('getOptValue / JsObject.get_opt (Phase 24b)', () => {
  test('returns value when x property is present', () => {
    expect(addon.getOptValue({ x: 42 })).toBe(42);
  });

  test('returns null when x property is missing', () => {
    expect(addon.getOptValue({})).toBeNull();
  });

  test('returns value for x=0 (falsy value still present)', () => {
    expect(addon.getOptValue({ x: 0 })).toBe(0);
  });

  test('returns value for x=false', () => {
    expect(addon.getOptValue({ x: false })).toBe(false);
  });

  test('returns value for x=null (JS null counts as present)', () => {
    // x is explicitly set to null — the key exists, value is JS null
    // get_opt detects the key exists and returns null (not the missing sentinel)
    expect(addon.getOptValue({ x: null })).toBeNull();
  });

  test('returns value for x=undefined (key present, value is undefined)', () => {
    const obj = {};
    Object.defineProperty(obj, 'x', { value: undefined, enumerable: true });
    // napi_has_named_property returns true even if value is undefined
    const result = addon.getOptValue(obj);
    // Key exists (has_property=true), so get_opt returns undefined napi_value
    // undefined passes through (not the null sentinel)
    expect(result).toBeUndefined();
  });

  test('ignores y and z properties, only reads x', () => {
    expect(addon.getOptValue({ y: 99, z: 100 })).toBeNull();
    expect(addon.getOptValue({ x: 7, y: 99 })).toBe(7);
  });

  test('returns string value when x is a string', () => {
    expect(addon.getOptValue({ x: 'hello' })).toBe('hello');
  });
});
