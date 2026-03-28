const addon = require('../index');

describe('nullable return types (Optional → T | null)', () => {
  describe('safeDivide', () => {
    test('returns number when divisor is non-zero', () => {
      expect(addon.safeDivide(10, 2)).toBe(5);
      expect(addon.safeDivide(7, 3)).toBeCloseTo(2.333, 2);
      expect(addon.safeDivide(-6, 2)).toBe(-3);
    });

    test('returns null when divisor is zero', () => {
      expect(addon.safeDivide(10, 0)).toBeNull();
      expect(addon.safeDivide(0, 0)).toBeNull();
    });

    test('throws on wrong arg type', () => {
      expect(() => addon.safeDivide('a', 1)).toThrow();
    });
  });

  describe('findName', () => {
    test('returns string when index is valid', () => {
      expect(addon.findName(['alice', 'bob', 'carol'], 0)).toBe('alice');
      expect(addon.findName(['alice', 'bob', 'carol'], 2)).toBe('carol');
    });

    test('returns null when index is out of bounds', () => {
      expect(addon.findName(['alice', 'bob'], 5)).toBeNull();
      expect(addon.findName(['alice', 'bob'], -1)).toBeNull();
    });

    test('returns null for empty array', () => {
      expect(addon.findName([], 0)).toBeNull();
    });

    test('throws on non-array first arg', () => {
      expect(() => addon.findName('not array', 0)).toThrow();
    });
  });
});
