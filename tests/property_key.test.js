const addon = require('../build/index.node');

// createPropertyKey — node_api_create_property_key_utf8 (N-API v10)

test('createPropertyKey returns a string value', () => {
  const key = addon.createPropertyKey('hello');
  expect(typeof key).toBe('string');
});

test('createPropertyKey result equals the input string', () => {
  expect(addon.createPropertyKey('world')).toBe('world');
  expect(addon.createPropertyKey('foo')).toBe('foo');
  expect(addon.createPropertyKey('')).toBe('');
});

test('createPropertyKey handles unicode input', () => {
  // ASCII subset — Latin-1 compatible
  expect(addon.createPropertyKey('name')).toBe('name');
  expect(addon.createPropertyKey('camelCase')).toBe('camelCase');
});

test('createPropertyKey result works as a property key', () => {
  const key = addon.createPropertyKey('x');
  const obj = { x: 42 };
  expect(obj[key]).toBe(42);
});

test('createPropertyKey result works for dynamic property set/get', () => {
  const key = addon.createPropertyKey('dynamicProp');
  const obj = {};
  obj[key] = 'value';
  expect(obj[key]).toBe('value');
  expect(obj['dynamicProp']).toBe('value');
});

test('createPropertyKey with longer property name', () => {
  const long = 'thisIsALongerPropertyNameForTesting';
  const key = addon.createPropertyKey(long);
  const obj = {};
  obj[key] = 'found';
  expect(obj[long]).toBe('found');
});

test('createPropertyKey result appears in Object.keys', () => {
  const key = addon.createPropertyKey('visible');
  const obj = {};
  obj[key] = true;
  expect(Object.keys(obj)).toContain('visible');
});

test('createPropertyKey result works with in operator', () => {
  const key = addon.createPropertyKey('check');
  const obj = { check: 1 };
  expect(key in obj).toBe(true);
});

test('two createPropertyKey calls with same input produce === values', () => {
  const a = addon.createPropertyKey('interned');
  const b = addon.createPropertyKey('interned');
  expect(a === b).toBe(true);
});

test('createPropertyKey with special characters', () => {
  const key = addon.createPropertyKey('my-prop.name');
  expect(key).toBe('my-prop.name');
  const obj = {};
  obj[key] = 42;
  expect(obj['my-prop.name']).toBe(42);
});

test('createPropertyKey throws on non-string input', () => {
  expect(() => addon.createPropertyKey(42)).toThrow();
  expect(() => addon.createPropertyKey(null)).toThrow();
});
