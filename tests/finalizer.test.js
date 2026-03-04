const addon = require('../build/index.node');

describe('napi_add_finalizer', () => {
  test('attachFinalizer does not throw on plain object', () => {
    expect(() => addon.attachFinalizer({})).not.toThrow();
  });

  test('attachFinalizer returns the same object', () => {
    const obj = { x: 1 };
    const result = addon.attachFinalizer(obj);
    expect(result).toBe(obj);
    expect(result.x).toBe(1);
  });

  test('attachFinalizer works on empty object', () => {
    const obj = {};
    expect(addon.attachFinalizer(obj)).toBe(obj);
  });

  test('attachFinalizer works on object with properties', () => {
    const obj = { a: 1, b: 'hello', c: [1, 2, 3] };
    const result = addon.attachFinalizer(obj);
    expect(result.a).toBe(1);
    expect(result.b).toBe('hello');
  });

  test('multiple attachFinalizer calls on different objects', () => {
    const obj1 = { id: 1 };
    const obj2 = { id: 2 };
    addon.attachFinalizer(obj1);
    addon.attachFinalizer(obj2);
    expect(obj1.id).toBe(1);
    expect(obj2.id).toBe(2);
  });
});
