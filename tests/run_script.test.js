const addon = require('../build/index.node');

describe('runScript', () => {
  test('evaluates simple arithmetic', () => {
    expect(addon.runScript('1 + 2')).toBe(3);
  });

  test('evaluates string expression', () => {
    expect(addon.runScript('"hello" + " " + "world"')).toBe('hello world');
  });

  test('evaluates object literal (wrapped in parens)', () => {
    const result = addon.runScript('({a: 1, b: 2})');
    expect(result).toEqual({ a: 1, b: 2 });
  });

  test('evaluates array literal', () => {
    const result = addon.runScript('[1, 2, 3]');
    expect(result).toEqual([1, 2, 3]);
  });

  test('evaluates boolean', () => {
    expect(addon.runScript('true')).toBe(true);
    expect(addon.runScript('false')).toBe(false);
  });

  test('evaluates null', () => {
    expect(addon.runScript('null')).toBe(null);
  });

  test('evaluates undefined', () => {
    expect(addon.runScript('undefined')).toBe(undefined);
  });

  test('can access global objects', () => {
    expect(addon.runScript('typeof Array')).toBe('function');
  });
});
