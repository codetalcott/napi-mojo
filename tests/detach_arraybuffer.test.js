const addon = require('../build/index.node');

describe('detachArrayBuffer', () => {
  test('isDetachedArrayBuffer returns false for normal ArrayBuffer', () => {
    const ab = new ArrayBuffer(16);
    expect(addon.isDetachedArrayBuffer(ab)).toBe(false);
  });

  test('detachArrayBuffer detaches an ArrayBuffer', () => {
    const ab = new ArrayBuffer(16);
    expect(addon.detachArrayBuffer(ab)).toBe(true);
    expect(addon.isDetachedArrayBuffer(ab)).toBe(true);
  });

  test('isDetachedArrayBuffer returns false for Mojo-created ArrayBuffer', () => {
    const ab = addon.createArrayBuffer(8);
    expect(addon.isDetachedArrayBuffer(ab)).toBe(false);
  });

  test('detached ArrayBuffer has zero byteLength', () => {
    const ab = new ArrayBuffer(32);
    addon.detachArrayBuffer(ab);
    expect(ab.byteLength).toBe(0);
  });
});
