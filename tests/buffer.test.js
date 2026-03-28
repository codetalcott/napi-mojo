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

test('createBufferCopy returns a Buffer equal to source', () => {
  const src = Buffer.from([10, 20, 30, 40]);
  const copy = addon.createBufferCopy(src);
  expect(Buffer.isBuffer(copy)).toBe(true);
  expect([...copy]).toEqual([10, 20, 30, 40]);
});

test('createBufferCopy produces an independent copy', () => {
  const src = Buffer.from([1, 2, 3]);
  const copy = addon.createBufferCopy(src);
  src[0] = 99;
  expect(copy[0]).toBe(1);
});

test('createBufferCopy works with empty Buffer', () => {
  const copy = addon.createBufferCopy(Buffer.alloc(0));
  expect(Buffer.isBuffer(copy)).toBe(true);
  expect(copy.length).toBe(0);
});

test('createBufferCopy throws on non-Buffer', () => {
  expect(() => addon.createBufferCopy('not a buffer')).toThrow();
});

// bufferFromArrayBuffer — node_api_create_buffer_from_arraybuffer (N-API v10)

test('bufferFromArrayBuffer returns a Buffer', () => {
  const ab = new ArrayBuffer(8);
  const buf = addon.bufferFromArrayBuffer(ab, 0, 8);
  expect(Buffer.isBuffer(buf)).toBe(true);
  expect(buf.length).toBe(8);
});

test('bufferFromArrayBuffer slice with offset and length', () => {
  const ab = new ArrayBuffer(8);
  const view = new Uint8Array(ab);
  view.set([0, 1, 2, 3, 4, 5, 6, 7]);
  const buf = addon.bufferFromArrayBuffer(ab, 2, 4);
  expect(buf.length).toBe(4);
  expect([...buf]).toEqual([2, 3, 4, 5]);
});

test('bufferFromArrayBuffer is zero-copy — mutations are shared', () => {
  const ab = new ArrayBuffer(4);
  const view = new Uint8Array(ab);
  view.set([10, 20, 30, 40]);
  const buf = addon.bufferFromArrayBuffer(ab, 0, 4);
  // Write through Buffer — should reflect in the ArrayBuffer
  buf[0] = 99;
  expect(view[0]).toBe(99);
});

test('bufferFromArrayBuffer zero-length slice', () => {
  const ab = new ArrayBuffer(4);
  const buf = addon.bufferFromArrayBuffer(ab, 0, 0);
  expect(Buffer.isBuffer(buf)).toBe(true);
  expect(buf.length).toBe(0);
});

test('bufferFromArrayBuffer reverse mutation — ArrayBuffer write visible in Buffer', () => {
  const ab = new ArrayBuffer(4);
  const buf = addon.bufferFromArrayBuffer(ab, 0, 4);
  const view = new Uint8Array(ab);
  view[2] = 77;
  expect(buf[2]).toBe(77);
});

test('bufferFromArrayBuffer full-size slice', () => {
  const ab = new ArrayBuffer(6);
  new Uint8Array(ab).set([1, 2, 3, 4, 5, 6]);
  const buf = addon.bufferFromArrayBuffer(ab, 0, 6);
  expect([...buf]).toEqual([1, 2, 3, 4, 5, 6]);
});

test('bufferFromArrayBuffer throws on out-of-bounds range', () => {
  const ab = new ArrayBuffer(4);
  expect(() => addon.bufferFromArrayBuffer(ab, 2, 4)).toThrow();
});
