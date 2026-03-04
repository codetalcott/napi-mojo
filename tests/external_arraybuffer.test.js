const addon = require('../build/index.node');

describe('External ArrayBuffer (zero-copy)', () => {
  test('createExternalArrayBuffer returns an ArrayBuffer', () => {
    const ab = addon.createExternalArrayBuffer(8);
    expect(addon.arrayBufferLength(ab)).toBe(8);
  });

  test('external ArrayBuffer has correct byte length', () => {
    expect(addon.arrayBufferLength(addon.createExternalArrayBuffer(16))).toBe(16);
  });

  test('external ArrayBuffer data is readable via Uint8Array', () => {
    const ab = addon.createExternalArrayBuffer(4);
    const u8 = new Uint8Array(ab);
    // Filled with incrementing bytes: 0, 1, 2, 3
    expect(u8[0]).toBe(0);
    expect(u8[1]).toBe(1);
    expect(u8[2]).toBe(2);
    expect(u8[3]).toBe(3);
  });

  test('external ArrayBuffer can be used with DataView', () => {
    const ab = addon.createExternalArrayBuffer(4);
    const dv = new DataView(ab);
    expect(dv.getUint8(0)).toBe(0);
    expect(dv.getUint8(3)).toBe(3);
  });

  test('external ArrayBuffer can be used with Float64Array', () => {
    const ab = addon.createExternalArrayBuffer(8);
    const f64 = new Float64Array(ab);
    // Just verify it doesn't throw - the bytes are 0-7 which is a valid float
    expect(f64.length).toBe(1);
  });

  test('multiple external ArrayBuffers are independent', () => {
    const ab1 = addon.createExternalArrayBuffer(4);
    const ab2 = addon.createExternalArrayBuffer(8);
    expect(addon.arrayBufferLength(ab1)).toBe(4);
    expect(addon.arrayBufferLength(ab2)).toBe(8);
    const u8a = new Uint8Array(ab1);
    const u8b = new Uint8Array(ab2);
    // Modifying one doesn't affect the other
    u8a[0] = 99;
    expect(u8b[0]).toBe(0);
  });

  test('external ArrayBuffer JS byteLength matches', () => {
    const ab = addon.createExternalArrayBuffer(32);
    expect(ab.byteLength).toBe(32);
  });
});
