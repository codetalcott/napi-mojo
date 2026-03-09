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

  describe('genericDoubleArray (parametric to_js_array[JsF64])', () => {
    test('doubles each element', () => {
      expect(addon.genericDoubleArray([1, 2, 3])).toEqual([2, 4, 6]);
    });

    test('empty array', () => {
      expect(addon.genericDoubleArray([])).toEqual([]);
    });

    test('matches concrete doubleArray', () => {
      const input = [1.5, -2, 0, 100];
      expect(addon.genericDoubleArray(input)).toEqual(addon.doubleArray(input));
    });
  });

  describe('genericReverseStrings (parametric to_js_array[JsStr])', () => {
    test('reverses array', () => {
      expect(addon.genericReverseStrings(['x', 'y', 'z'])).toEqual(['z', 'y', 'x']);
    });

    test('matches concrete reverseStrings', () => {
      const input = ['hello', 'world', 'foo'];
      expect(addon.genericReverseStrings(input)).toEqual(addon.reverseStrings(input));
    });
  });

  describe('objectFromArrays', () => {
    test('builds object from parallel arrays', () => {
      expect(addon.objectFromArrays(['a', 'b'], [1, 2])).toEqual({ a: 1, b: 2 });
    });

    test('empty arrays produce empty object', () => {
      expect(addon.objectFromArrays([], [])).toEqual({});
    });

    test('throws on mismatched lengths', () => {
      try {
        addon.objectFromArrays(['a', 'b'], [1]);
        fail('should have thrown');
      } catch (e) {
        expect(e.name).toBe('TypeError');
      }
    });
  });

  describe('objectToArrays', () => {
    test('extracts keys and values from object', () => {
      const result = addon.objectToArrays({ x: 10, y: 20 });
      expect(result.keys).toEqual(['x', 'y']);
      expect(result.values).toEqual([10, 20]);
    });

    test('empty object', () => {
      const result = addon.objectToArrays({});
      expect(result.keys).toEqual([]);
      expect(result.values).toEqual([]);
    });

    test('round-trips through objectFromArrays', () => {
      const obj = { foo: 1.5, bar: 2.5 };
      const { keys, values } = addon.objectToArrays(obj);
      expect(addon.objectFromArrays(keys, values)).toEqual(obj);
    });
  });
});
