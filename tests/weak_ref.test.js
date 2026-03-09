const addon = require('../build/index.node');

describe('testWeakRef', () => {
  test('returns the value while object is alive', () => {
    const obj = { x: 42 };
    const retrieved = addon.testWeakRef(obj);
    expect(retrieved).toEqual({ x: 42 });
  });

  test('works with nested objects', () => {
    const obj = { a: { b: 'hello' } };
    const retrieved = addon.testWeakRef(obj);
    expect(retrieved.a.b).toBe('hello');
  });

  test('works with arrays', () => {
    const arr = [1, 2, 3];
    const retrieved = addon.testWeakRef(arr);
    expect(retrieved).toEqual([1, 2, 3]);
  });
});
