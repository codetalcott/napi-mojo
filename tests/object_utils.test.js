const addon = require('../build/index.node');

// --- getKeys ---
test('getKeys({a: 1, b: 2, c: 3}) returns ["a", "b", "c"]', () => {
  const keys = addon.getKeys({a: 1, b: 2, c: 3});
  expect(keys).toEqual(['a', 'b', 'c']);
});

test('getKeys({}) returns []', () => {
  expect(addon.getKeys({})).toEqual([]);
});

test('getKeys with non-object throws', () => {
  expect(() => addon.getKeys(42)).toThrow();
});

test('getKeys only returns own enumerable properties', () => {
  const obj = Object.create({inherited: true});
  obj.own = 1;
  const keys = addon.getKeys(obj);
  expect(keys).toEqual(['own']);
  expect(keys).not.toContain('inherited');
});

// --- hasOwn ---
test('hasOwn({x: 1}, "x") returns true', () => {
  expect(addon.hasOwn({x: 1}, 'x')).toBe(true);
});

test('hasOwn({x: 1}, "y") returns false', () => {
  expect(addon.hasOwn({x: 1}, 'y')).toBe(false);
});

test('hasOwn does not find inherited properties', () => {
  const obj = Object.create({inherited: true});
  obj.own = 1;
  expect(addon.hasOwn(obj, 'inherited')).toBe(false);
  expect(addon.hasOwn(obj, 'own')).toBe(true);
});

test('hasOwn with non-object throws', () => {
  expect(() => addon.hasOwn(42, 'x')).toThrow();
});

// --- deleteProperty ---
test('deleteProperty removes key and returns modified object', () => {
  const obj = {a: 1, b: 2};
  const result = addon.deleteProperty(obj, 'a');
  expect(result).toEqual({b: 2});
  expect('a' in result).toBe(false);
});

test('deleteProperty on missing key returns object unchanged', () => {
  const obj = {x: 1};
  const result = addon.deleteProperty(obj, 'missing');
  expect(result).toEqual({x: 1});
});

test('deleteProperty with non-object throws', () => {
  expect(() => addon.deleteProperty(42, 'x')).toThrow();
});

// --- getPrototype ---
test('getPrototype of plain object is Object.prototype', () => {
  const proto = addon.getPrototype({});
  expect(proto).toBe(Object.prototype);
});

test('getPrototype of instance is constructor.prototype', () => {
  class MyClass { myMethod() {} }
  const obj = new MyClass();
  const proto = addon.getPrototype(obj);
  expect(proto).toBe(MyClass.prototype);
  expect(typeof proto.myMethod).toBe('function');
});

test('getPrototype of Object.create(null) is null', () => {
  const obj = Object.create(null);
  expect(addon.getPrototype(obj)).toBeNull();
});

test('getPrototype with non-object throws', () => {
  expect(() => addon.getPrototype(42)).toThrow();
});
