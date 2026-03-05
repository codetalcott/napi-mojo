const addon = require('../build/index.node');

describe('Symbol as property key', () => {
  test('setPropertyByKey with symbol key', () => {
    const obj = addon.createObject();
    const sym = addon.createSymbol('myKey');
    const result = addon.setPropertyByKey(obj, sym, 42);
    expect(result).toBe(obj);
  });

  test('hasPropertyByKey with symbol key returns true', () => {
    const obj = addon.createObject();
    const sym = addon.createSymbol('myKey');
    addon.setPropertyByKey(obj, sym, 'hello');
    expect(addon.hasPropertyByKey(obj, sym)).toBe(true);
  });

  test('hasPropertyByKey with unused symbol returns false', () => {
    const obj = addon.createObject();
    const sym = addon.createSymbol('unused');
    expect(addon.hasPropertyByKey(obj, sym)).toBe(false);
  });

  test('symbol keys do not appear in getKeys()', () => {
    const obj = addon.createObject();
    const sym = addon.createSymbol('hidden');
    addon.setPropertyByKey(obj, sym, 99);
    addon.setPropertyByKey(obj, 'visible', 1);
    const keys = addon.getKeys(obj);
    expect(keys).toEqual(['visible']);
  });
});
