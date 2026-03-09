'use strict';
const addon = require('../build/index.node');

describe('Phase 27: code generator type extensions', () => {
  // uint32
  test('exampleAddUInt32: adds two unsigned 32-bit integers', () => {
    expect(addon.exampleAddUInt32(10, 20)).toBe(30);
    expect(addon.exampleAddUInt32(0, 0)).toBe(0);
    expect(addon.exampleAddUInt32(2147483647, 1)).toBe(2147483648);
  });

  test('exampleAddUInt32: throws TypeError on non-number', () => {
    expect(() => addon.exampleAddUInt32('a', 1)).toThrow();
  });

  // int64
  test('exampleDoubleInt64: doubles an int64 value', () => {
    expect(addon.exampleDoubleInt64(21)).toBe(42);
    expect(addon.exampleDoubleInt64(-5)).toBe(-10);
    expect(addon.exampleDoubleInt64(0)).toBe(0);
  });

  test('exampleDoubleInt64: throws TypeError on non-number', () => {
    expect(() => addon.exampleDoubleInt64('x')).toThrow();
  });

  // bool (alias for boolean)
  test('exampleNegateBool: negates a boolean', () => {
    expect(addon.exampleNegateBool(true)).toBe(false);
    expect(addon.exampleNegateBool(false)).toBe(true);
  });

  test('exampleNegateBool: throws TypeError on non-boolean', () => {
    expect(() => addon.exampleNegateBool(1)).toThrow();
  });

  // object
  test('exampleHasKey: checks if object has key', () => {
    expect(addon.exampleHasKey({ x: 1 }, 'x')).toBe(true);
    expect(addon.exampleHasKey({ x: 1 }, 'y')).toBe(false);
    expect(addon.exampleHasKey({}, 'z')).toBe(false);
  });

  test('exampleHasKey: throws TypeError on non-object arg1', () => {
    expect(() => addon.exampleHasKey(42, 'x')).toThrow();
  });

  // array
  test('exampleArrayLen: returns length of array', () => {
    expect(addon.exampleArrayLen([1, 2, 3])).toBe(3);
    expect(addon.exampleArrayLen([])).toBe(0);
    expect(addon.exampleArrayLen([42])).toBe(1);
  });

  test('exampleArrayLen: throws TypeError on non-array', () => {
    expect(() => addon.exampleArrayLen({})).toThrow();
    expect(() => addon.exampleArrayLen('abc')).toThrow();
  });

  // nullable (any?)
  test('exampleNullableEcho: passes any value through without type check', () => {
    expect(addon.exampleNullableEcho(42)).toBe(42);
    expect(addon.exampleNullableEcho('hello')).toBe('hello');
    expect(addon.exampleNullableEcho(null)).toBeNull();
    expect(addon.exampleNullableEcho(undefined)).toBeUndefined();
    expect(addon.exampleNullableEcho(true)).toBe(true);
  });
});
