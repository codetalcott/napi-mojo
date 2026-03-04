const addon = require('../build/index.node');

// --- strictEquals ---
test('strictEquals(1, 1) returns true', () => {
  expect(addon.strictEquals(1, 1)).toBe(true);
});

test('strictEquals(1, "1") returns false', () => {
  expect(addon.strictEquals(1, '1')).toBe(false);
});

test('strictEquals(null, null) returns true', () => {
  expect(addon.strictEquals(null, null)).toBe(true);
});

test('strictEquals(null, undefined) returns false', () => {
  expect(addon.strictEquals(null, undefined)).toBe(false);
});

test('strictEquals with same object reference returns true', () => {
  const obj = {a: 1};
  expect(addon.strictEquals(obj, obj)).toBe(true);
});

test('strictEquals with different objects returns false', () => {
  expect(addon.strictEquals({a: 1}, {a: 1})).toBe(false);
});

// --- isInstanceOf ---
test('isInstanceOf(new Date(), Date) returns true', () => {
  expect(addon.isInstanceOf(new Date(), Date)).toBe(true);
});

test('isInstanceOf({}, Object) returns true', () => {
  expect(addon.isInstanceOf({}, Object)).toBe(true);
});

test('isInstanceOf(42, Number) returns false (primitive)', () => {
  expect(addon.isInstanceOf(42, Number)).toBe(false);
});

test('isInstanceOf with custom class', () => {
  class MyClass {}
  const obj = new MyClass();
  expect(addon.isInstanceOf(obj, MyClass)).toBe(true);
  expect(addon.isInstanceOf(obj, Date)).toBe(false);
});

// --- freezeObject ---
test('freezeObject prevents property modification', () => {
  const obj = addon.freezeObject({x: 1, y: 2});
  expect(Object.isFrozen(obj)).toBe(true);
});

test('freezeObject returns the same object', () => {
  const input = {a: 1};
  const result = addon.freezeObject(input);
  expect(result).toBe(input);
  expect(result.a).toBe(1);
});

test('freezeObject with non-object throws', () => {
  expect(() => addon.freezeObject(42)).toThrow();
});

// --- sealObject ---
test('sealObject prevents adding new properties', () => {
  const obj = addon.sealObject({x: 1});
  expect(Object.isSealed(obj)).toBe(true);
});

test('sealObject still allows modification of existing values', () => {
  const obj = addon.sealObject({x: 1});
  obj.x = 42;
  expect(obj.x).toBe(42);
});

test('sealObject returns the same object', () => {
  const input = {b: 2};
  const result = addon.sealObject(input);
  expect(result).toBe(input);
});

test('sealObject with non-object throws', () => {
  expect(() => addon.sealObject('hello')).toThrow();
});
