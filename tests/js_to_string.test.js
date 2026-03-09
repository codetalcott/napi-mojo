'use strict';
const addon = require('../build/index.node');

describe('toJsString / js_to_string (Phase 24c)', () => {
  test('passes string through unchanged', () => {
    expect(addon.toJsString('hello')).toBe('hello');
  });

  test('passes empty string through', () => {
    expect(addon.toJsString('')).toBe('');
  });

  test('converts number to string', () => {
    expect(addon.toJsString(42)).toBe('42');
    expect(addon.toJsString(3.14)).toBe('3.14');
    expect(addon.toJsString(0)).toBe('0');
    expect(addon.toJsString(-1)).toBe('-1');
  });

  test('converts boolean to string', () => {
    expect(addon.toJsString(true)).toBe('true');
    expect(addon.toJsString(false)).toBe('false');
  });

  test('converts null to string', () => {
    expect(addon.toJsString(null)).toBe('null');
  });

  test('converts undefined to string', () => {
    expect(addon.toJsString(undefined)).toBe('undefined');
  });

  test('converts object to string via toString', () => {
    const result = addon.toJsString({});
    expect(result).toBe('[object Object]');
  });

  test('converts array to string (comma-joined)', () => {
    expect(addon.toJsString([1, 2, 3])).toBe('1,2,3');
  });

  test('throws TypeError on Symbol (matches JS behavior)', () => {
    expect(() => addon.toJsString(Symbol('x'))).toThrow();
  });

  test('handles unicode strings', () => {
    expect(addon.toJsString('日本語')).toBe('日本語');
    expect(addon.toJsString('🎉')).toBe('🎉');
  });
});
