const addon = require('../build/index.node');

test('createArrayBuffer(8) returns an ArrayBuffer with byteLength 8', () => {
  const buf = addon.createArrayBuffer(8);
  expect(buf instanceof ArrayBuffer).toBe(true);
  expect(buf.byteLength).toBe(8);
});

test('createArrayBuffer(0) returns empty ArrayBuffer', () => {
  const buf = addon.createArrayBuffer(0);
  expect(buf instanceof ArrayBuffer).toBe(true);
  expect(buf.byteLength).toBe(0);
});

test('arrayBufferLength returns the byte length', () => {
  const buf = new ArrayBuffer(16);
  expect(addon.arrayBufferLength(buf)).toBe(16);
});

test('ArrayBuffer data can be written and read via Uint8Array view', () => {
  const buf = addon.createArrayBuffer(4);
  const view = new Uint8Array(buf);
  // Mojo callback fills with incrementing values
  expect(view[0]).toBe(0);
  expect(view[1]).toBe(1);
  expect(view[2]).toBe(2);
  expect(view[3]).toBe(3);
});
