const addon = require('../index');

describe('mojo_fn expanded type coverage', () => {
  test('negateBoolPure: boolean round-trip', () => {
    expect(addon.negateBoolPure(true)).toBe(false);
    expect(addon.negateBoolPure(false)).toBe(true);
  });

  test('negateBoolPure: type error on non-boolean', () => {
    expect(() => addon.negateBoolPure(42)).toThrow();
  });

  test('addInt32Pure: int32 round-trip', () => {
    expect(addon.addInt32Pure(10, 20)).toBe(30);
    expect(addon.addInt32Pure(-5, 3)).toBe(-2);
  });

  test('addInt32Pure: type error on string', () => {
    expect(() => addon.addInt32Pure('a', 1)).toThrow();
  });

  test('describePure: mixed string + number args', () => {
    expect(addon.describePure('Alice', 30)).toBe('Alice is 30');
    expect(addon.describePure('Bob', 0)).toBe('Bob is 0');
  });

  test('describePure: type error on wrong arg types', () => {
    expect(() => addon.describePure(42, 30)).toThrow();
    expect(() => addon.describePure('Alice', 'thirty')).toThrow();
  });

  test('reverseStringsPure: string[] round-trip', () => {
    expect(addon.reverseStringsPure(['a', 'b', 'c'])).toEqual(['c', 'b', 'a']);
    expect(addon.reverseStringsPure([])).toEqual([]);
    expect(addon.reverseStringsPure(['only'])).toEqual(['only']);
  });

  test('reverseStringsPure: type error on non-array', () => {
    expect(() => addon.reverseStringsPure('not an array')).toThrow();
  });
});
