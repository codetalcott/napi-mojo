const addon = require('../build/index.node');

describe('Set/Has Property by napi_value Key', () => {
  // setPropertyByKey — sets obj[key] = value using napi_set_property

  test('setPropertyByKey with string key', () => {
    const obj = {};
    addon.setPropertyByKey(obj, 'x', 42);
    expect(obj.x).toBe(42);
  });

  test('setPropertyByKey with symbol key', () => {
    const sym = Symbol('test');
    const obj = {};
    addon.setPropertyByKey(obj, sym, 'hello');
    expect(obj[sym]).toBe('hello');
  });

  test('setPropertyByKey overwrites existing property', () => {
    const obj = { x: 1 };
    addon.setPropertyByKey(obj, 'x', 99);
    expect(obj.x).toBe(99);
  });

  test('setPropertyByKey with multiple keys', () => {
    const obj = {};
    addon.setPropertyByKey(obj, 'a', 1);
    addon.setPropertyByKey(obj, 'b', 2);
    expect(obj.a).toBe(1);
    expect(obj.b).toBe(2);
  });

  test('setPropertyByKey returns the mutated object', () => {
    const obj = {};
    const result = addon.setPropertyByKey(obj, 'key', 'val');
    expect(result).toBe(obj);
    expect(result.key).toBe('val');
  });

  // hasPropertyByKey — checks if key exists using napi_has_property

  test('hasPropertyByKey returns true for own property', () => {
    expect(addon.hasPropertyByKey({ x: 1 }, 'x')).toBe(true);
  });

  test('hasPropertyByKey returns false for missing property', () => {
    expect(addon.hasPropertyByKey({}, 'x')).toBe(false);
  });

  test('hasPropertyByKey with symbol key', () => {
    const sym = Symbol('test');
    const obj = { [sym]: true };
    expect(addon.hasPropertyByKey(obj, sym)).toBe(true);
  });

  test('hasPropertyByKey finds inherited properties', () => {
    // napi_has_property walks the prototype chain (unlike hasOwn)
    const parent = { inherited: true };
    const child = Object.create(parent);
    expect(addon.hasPropertyByKey(child, 'inherited')).toBe(true);
  });

  test('hasPropertyByKey returns false for missing symbol key', () => {
    const sym = Symbol('missing');
    expect(addon.hasPropertyByKey({}, sym)).toBe(false);
  });
});
