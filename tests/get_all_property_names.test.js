const addon = require('../build/index.node');

// napi_key_collection_mode
const NAPI_KEY_INCLUDE_PROTOTYPES = 0;
const NAPI_KEY_OWN_ONLY = 1;

// napi_key_filter bitmask
const NAPI_KEY_ALL_PROPERTIES = 0;
const NAPI_KEY_WRITABLE = 1;
const NAPI_KEY_ENUMERABLE = 2;
const NAPI_KEY_CONFIGURABLE = 4;
const NAPI_KEY_SKIP_STRINGS = 8;
const NAPI_KEY_SKIP_SYMBOLS = 16;

// napi_key_conversion
const NAPI_KEY_KEEP_NUMBERS = 0;
const NAPI_KEY_NUMBERS_TO_STRINGS = 1;

describe('getAllPropertyNames', () => {
  test('OWN_ONLY + ENUMERABLE returns own enumerable string keys', () => {
    const obj = { a: 1, b: 2 };
    const keys = addon.getAllPropertyNames(
      obj, NAPI_KEY_OWN_ONLY,
      NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
      NAPI_KEY_NUMBERS_TO_STRINGS
    );
    expect(keys.sort()).toEqual(['a', 'b']);
  });

  test('INCLUDE_PROTOTYPES includes inherited keys', () => {
    const parent = { inherited: true };
    const child = Object.create(parent);
    child.own = true;
    const keys = addon.getAllPropertyNames(
      child, NAPI_KEY_INCLUDE_PROTOTYPES,
      NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
      NAPI_KEY_NUMBERS_TO_STRINGS
    );
    expect(keys).toContain('own');
    expect(keys).toContain('inherited');
  });

  test('OWN_ONLY excludes inherited keys', () => {
    const parent = { inherited: true };
    const child = Object.create(parent);
    child.own = true;
    const keys = addon.getAllPropertyNames(
      child, NAPI_KEY_OWN_ONLY,
      NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
      NAPI_KEY_NUMBERS_TO_STRINGS
    );
    expect(keys).toContain('own');
    expect(keys).not.toContain('inherited');
  });

  test('returns array', () => {
    const obj = { x: 1 };
    const keys = addon.getAllPropertyNames(
      obj, NAPI_KEY_OWN_ONLY,
      NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
      NAPI_KEY_NUMBERS_TO_STRINGS
    );
    expect(Array.isArray(keys)).toBe(true);
  });

  test('empty object returns empty array', () => {
    const obj = Object.create(null);
    const keys = addon.getAllPropertyNames(
      obj, NAPI_KEY_OWN_ONLY,
      NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
      NAPI_KEY_NUMBERS_TO_STRINGS
    );
    expect(keys).toEqual([]);
  });

  test('SKIP_SYMBOLS excludes symbol keys', () => {
    const obj = { str: 1 };
    const sym = Symbol('test');
    obj[sym] = 2;
    const keys = addon.getAllPropertyNames(
      obj, NAPI_KEY_OWN_ONLY,
      NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
      NAPI_KEY_NUMBERS_TO_STRINGS
    );
    expect(keys).toEqual(['str']);
  });
});
