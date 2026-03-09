'use strict';
const addon = require('../build/index.node');

describe('collection helpers', () => {
  describe('sumJsArray', () => {
    test('sums a number array', () => {
      expect(addon.sumJsArray([1, 2, 3, 4, 5])).toBe(15);
    });

    test('returns 0 for empty array', () => {
      expect(addon.sumJsArray([])).toBe(0);
    });

    test('handles floats', () => {
      expect(addon.sumJsArray([1.5, 2.5])).toBe(4);
    });

    test('throws TypeError on non-array', () => {
      try {
        addon.sumJsArray(42);
        fail('should have thrown');
      } catch (e) {
        expect(e.name).toBe('TypeError');
      }
    });
  });

  describe('doubleArray', () => {
    test('doubles each element', () => {
      expect(addon.doubleArray([1, 2, 3])).toEqual([2, 4, 6]);
    });

    test('returns empty array for empty input', () => {
      expect(addon.doubleArray([])).toEqual([]);
    });

    test('handles negative numbers', () => {
      expect(addon.doubleArray([-1, 0, 1])).toEqual([-2, 0, 2]);
    });

    test('throws TypeError on non-array', () => {
      try {
        addon.doubleArray('not an array');
        fail('should have thrown');
      } catch (e) {
        expect(e.name).toBe('TypeError');
      }
    });
  });

  describe('joinStrings', () => {
    test('joins with separator', () => {
      expect(addon.joinStrings(['a', 'b', 'c'], ', ')).toBe('a, b, c');
    });

    test('joins with empty separator', () => {
      expect(addon.joinStrings(['foo', 'bar'], '')).toBe('foobar');
    });

    test('single element', () => {
      expect(addon.joinStrings(['hello'], '-')).toBe('hello');
    });

    test('empty array', () => {
      expect(addon.joinStrings([], ',')).toBe('');
    });
  });

  describe('reverseStrings', () => {
    test('reverses array', () => {
      expect(addon.reverseStrings(['a', 'b', 'c'])).toEqual(['c', 'b', 'a']);
    });

    test('single element unchanged', () => {
      expect(addon.reverseStrings(['only'])).toEqual(['only']);
    });

    test('empty array', () => {
      expect(addon.reverseStrings([])).toEqual([]);
    });

    test('throws TypeError on non-array', () => {
      try {
        addon.reverseStrings('not an array');
        fail('should have thrown');
      } catch (e) {
        expect(e.name).toBe('TypeError');
      }
    });
  });
});
