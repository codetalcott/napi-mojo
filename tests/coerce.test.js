const addon = require('../build/index.node');

// --- coerceToBool (equivalent to Boolean(value)) ---

test('coerceToBool(1) returns true', () => {
  expect(addon.coerceToBool(1)).toBe(true);
});

test('coerceToBool(0) returns false', () => {
  expect(addon.coerceToBool(0)).toBe(false);
});

test('coerceToBool("") returns false', () => {
  expect(addon.coerceToBool("")).toBe(false);
});

test('coerceToBool("hello") returns true', () => {
  expect(addon.coerceToBool("hello")).toBe(true);
});

test('coerceToBool(null) returns false', () => {
  expect(addon.coerceToBool(null)).toBe(false);
});

test('coerceToBool(undefined) returns false', () => {
  expect(addon.coerceToBool(undefined)).toBe(false);
});

test('coerceToBool({}) returns true', () => {
  expect(addon.coerceToBool({})).toBe(true);
});

test('coerceToBool([]) returns true', () => {
  expect(addon.coerceToBool([])).toBe(true);
});

// --- coerceToNumber (equivalent to Number(value)) ---

test('coerceToNumber("42") returns 42', () => {
  expect(addon.coerceToNumber("42")).toBe(42);
});

test('coerceToNumber(true) returns 1', () => {
  expect(addon.coerceToNumber(true)).toBe(1);
});

test('coerceToNumber(false) returns 0', () => {
  expect(addon.coerceToNumber(false)).toBe(0);
});

test('coerceToNumber(null) returns 0', () => {
  expect(addon.coerceToNumber(null)).toBe(0);
});

test('coerceToNumber("hello") returns NaN', () => {
  expect(addon.coerceToNumber("hello")).toBeNaN();
});

test('coerceToNumber(undefined) returns NaN', () => {
  expect(addon.coerceToNumber(undefined)).toBeNaN();
});

test('coerceToNumber("") returns 0', () => {
  expect(addon.coerceToNumber("")).toBe(0);
});

test('coerceToNumber with Symbol throws TypeError', () => {
  try {
    addon.coerceToNumber(Symbol('test'));
    expect(true).toBe(false); // Should not reach here
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});

// --- coerceToString (equivalent to String(value)) ---

test('coerceToString(42) returns "42"', () => {
  expect(addon.coerceToString(42)).toBe('42');
});

test('coerceToString(true) returns "true"', () => {
  expect(addon.coerceToString(true)).toBe('true');
});

test('coerceToString(false) returns "false"', () => {
  expect(addon.coerceToString(false)).toBe('false');
});

test('coerceToString(null) returns "null"', () => {
  expect(addon.coerceToString(null)).toBe('null');
});

test('coerceToString(undefined) returns "undefined"', () => {
  expect(addon.coerceToString(undefined)).toBe('undefined');
});

test('coerceToString({}) returns "[object Object]"', () => {
  expect(addon.coerceToString({})).toBe('[object Object]');
});

test('coerceToString(3.14) returns "3.14"', () => {
  expect(addon.coerceToString(3.14)).toBe('3.14');
});

test('coerceToString with Symbol throws TypeError', () => {
  try {
    addon.coerceToString(Symbol('test'));
    expect(true).toBe(false); // Should not reach here
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});

// --- coerceToObject (equivalent to Object(value)) ---

test('coerceToObject(42) returns Number object', () => {
  const result = addon.coerceToObject(42);
  expect(typeof result).toBe('object');
  expect(result.valueOf()).toBe(42);
});

test('coerceToObject("hello") returns String object', () => {
  const result = addon.coerceToObject("hello");
  expect(typeof result).toBe('object');
  expect(result.valueOf()).toBe("hello");
});

test('coerceToObject(true) returns Boolean object', () => {
  const result = addon.coerceToObject(true);
  expect(typeof result).toBe('object');
  expect(result.valueOf()).toBe(true);
});

test('coerceToObject({x:1}) returns same object', () => {
  const obj = { x: 1 };
  const result = addon.coerceToObject(obj);
  expect(result).toBe(obj);
  expect(result.x).toBe(1);
});

test('coerceToObject(null) throws TypeError', () => {
  try {
    addon.coerceToObject(null);
    expect(true).toBe(false); // Should not reach here
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});

test('coerceToObject(undefined) throws TypeError', () => {
  try {
    addon.coerceToObject(undefined);
    expect(true).toBe(false); // Should not reach here
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});
