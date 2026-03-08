const addon = require('../build/index.node');

describe('Generated functions (code generator pipeline)', () => {
  // --- exampleAdd ---

  test('exampleAdd(2, 3) returns 5', () => {
    expect(addon.exampleAdd(2, 3)).toBe(5);
  });

  test('exampleAdd(0, 0) returns 0', () => {
    expect(addon.exampleAdd(0, 0)).toBe(0);
  });

  test('exampleAdd(-1, 1) returns 0', () => {
    expect(addon.exampleAdd(-1, 1)).toBe(0);
  });

  test('exampleAdd(1.5, 2.5) returns 4', () => {
    expect(addon.exampleAdd(1.5, 2.5)).toBe(4);
  });

  test('exampleAdd with string arg throws TypeError', () => {
    try {
      addon.exampleAdd('hello', 1);
      expect(true).toBe(false);
    } catch (e) {
      expect(e.name).toBe('TypeError');
      expect(e.message).toContain('expected number');
    }
  });

  test('exampleAdd with string second arg throws TypeError', () => {
    try {
      addon.exampleAdd(1, 'hello');
      expect(true).toBe(false);
    } catch (e) {
      expect(e.name).toBe('TypeError');
      expect(e.message).toContain('expected number');
    }
  });

  // --- exampleGreet ---

  test('exampleGreet("Alice") returns "Hello, Alice!"', () => {
    expect(addon.exampleGreet('Alice')).toBe('Hello, Alice!');
  });

  test('exampleGreet("") returns "Hello, !"', () => {
    expect(addon.exampleGreet('')).toBe('Hello, !');
  });

  test('exampleGreet with number arg throws TypeError', () => {
    try {
      addon.exampleGreet(42);
      expect(true).toBe(false);
    } catch (e) {
      expect(e.name).toBe('TypeError');
      expect(e.message).toContain('expected string');
    }
  });

  // --- exampleIsPositive ---

  test('exampleIsPositive(1) returns true', () => {
    expect(addon.exampleIsPositive(1)).toBe(true);
  });

  test('exampleIsPositive(-1) returns false', () => {
    expect(addon.exampleIsPositive(-1)).toBe(false);
  });

  test('exampleIsPositive(0) returns false', () => {
    expect(addon.exampleIsPositive(0)).toBe(false);
  });

  test('exampleIsPositive with string arg throws TypeError', () => {
    try {
      addon.exampleIsPositive('hello');
      expect(true).toBe(false);
    } catch (e) {
      expect(e.name).toBe('TypeError');
      expect(e.message).toContain('expected number');
    }
  });
});
