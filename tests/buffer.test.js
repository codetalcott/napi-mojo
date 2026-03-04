const addon = require('../build/index.node');

test('sumBuffer sums bytes of a Buffer', () => {
  expect(addon.sumBuffer(Buffer.from([1, 2, 3]))).toBe(6);
});

test('sumBuffer of empty Buffer returns 0', () => {
  expect(addon.sumBuffer(Buffer.alloc(0))).toBe(0);
});

test('sumBuffer throws on non-buffer', () => {
  expect(() => addon.sumBuffer('not a buffer')).toThrow();
});

test('createBuffer(5) returns Buffer with incrementing values', () => {
  const buf = addon.createBuffer(5);
  expect(Buffer.isBuffer(buf)).toBe(true);
  expect(buf.length).toBe(5);
  expect([...buf]).toEqual([0, 1, 2, 3, 4]);
});

test('createBuffer(0) returns empty Buffer', () => {
  const buf = addon.createBuffer(0);
  expect(Buffer.isBuffer(buf)).toBe(true);
  expect(buf.length).toBe(0);
});

test('createBuffer returns a Buffer instance', () => {
  const buf = addon.createBuffer(3);
  expect(Buffer.isBuffer(buf)).toBe(true);
});
