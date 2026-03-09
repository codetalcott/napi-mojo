const addon = require('../build/index.node');

describe('typeTagObject / checkObjectTypeTag', () => {
  test('tagging an object and checking returns true', () => {
    const obj = {};
    addon.typeTagObject(obj, 1234, 5678);
    expect(addon.checkObjectTypeTag(obj, 1234, 5678)).toBe(true);
  });

  test('checking with wrong tag returns false', () => {
    const obj = {};
    addon.typeTagObject(obj, 1234, 5678);
    expect(addon.checkObjectTypeTag(obj, 9999, 5678)).toBe(false);
    expect(addon.checkObjectTypeTag(obj, 1234, 9999)).toBe(false);
  });

  test('checking untagged object returns false', () => {
    const obj = {};
    expect(addon.checkObjectTypeTag(obj, 1234, 5678)).toBe(false);
  });

  test('different objects can have different tags', () => {
    const obj1 = {};
    const obj2 = {};
    addon.typeTagObject(obj1, 100, 200);
    addon.typeTagObject(obj2, 300, 400);
    expect(addon.checkObjectTypeTag(obj1, 100, 200)).toBe(true);
    expect(addon.checkObjectTypeTag(obj2, 300, 400)).toBe(true);
    expect(addon.checkObjectTypeTag(obj1, 300, 400)).toBe(false);
  });

  test('tagging with zero values works', () => {
    const obj = {};
    addon.typeTagObject(obj, 0, 0);
    expect(addon.checkObjectTypeTag(obj, 0, 0)).toBe(true);
  });
});
