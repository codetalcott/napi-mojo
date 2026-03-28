const addon = require('../build/index.node');

// createExternalString — node_api_create_external_string_latin1 (N-API v10)

test('createExternalString returns a string value', () => {
  const result = addon.createExternalString('hello');
  expect(typeof result).toBe('string');
});

test('createExternalString result equals the input', () => {
  expect(addon.createExternalString('hello')).toBe('hello');
  expect(addon.createExternalString('world')).toBe('world');
  expect(addon.createExternalString('')).toBe('');
});

test('createExternalString handles various ASCII strings', () => {
  const inputs = ['foo', 'bar', 'test123', 'hello world', 'camelCase'];
  for (const s of inputs) {
    expect(addon.createExternalString(s)).toBe(s);
  }
});

test('createExternalString result behaves like a normal string', () => {
  const s = addon.createExternalString('hello');
  expect(s.length).toBe(5);
  expect(s.toUpperCase()).toBe('HELLO');
  expect(s + ' world').toBe('hello world');
});

test('createExternalString with single character', () => {
  expect(addon.createExternalString('a')).toBe('a');
});

test('createExternalString with longer string', () => {
  const long = 'a'.repeat(1000);
  const result = addon.createExternalString(long);
  expect(result).toBe(long);
  expect(result.length).toBe(1000);
});

test('createExternalString result compares correctly with ===', () => {
  const s = addon.createExternalString('test');
  expect(s === 'test').toBe(true);
  expect(s === 'other').toBe(false);
});

test('createExternalString result works as object key', () => {
  const key = addon.createExternalString('myKey');
  const obj = {};
  obj[key] = 99;
  expect(obj['myKey']).toBe(99);
});

test('createExternalString handles Latin-1 extended characters', () => {
  // Characters in the 128-255 range: valid Latin-1, multi-byte in UTF-8
  expect(addon.createExternalString('café')).toBe('café');
  expect(addon.createExternalString('naïve')).toBe('naïve');
  expect(addon.createExternalString('©')).toBe('©');
  expect(addon.createExternalString('ñ')).toBe('ñ');
  expect(addon.createExternalString('über')).toBe('über');
});

test('createExternalString Latin-1 string has correct length', () => {
  // 'café' is 4 JS characters — should be 4 Latin-1 bytes
  const s = addon.createExternalString('café');
  expect(s.length).toBe(4);
});

test('createExternalString throws on non-string input', () => {
  expect(() => addon.createExternalString(42)).toThrow();
  expect(() => addon.createExternalString(null)).toThrow();
});
