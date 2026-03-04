const addon = require('../build/index.node');

describe('DataView support', () => {
  test('createDataView returns a DataView', () => {
    const ab = new ArrayBuffer(16);
    const dv = addon.createDataView(ab, 0, 16);
    // Jest cross-realm: instanceof DataView fails, use duck-typing
    expect(typeof dv.getUint8).toBe('function');
    expect(typeof dv.setUint8).toBe('function');
    expect(dv.byteLength).toBe(16);
  });

  test('getDataViewInfo returns correct byteLength', () => {
    const ab = new ArrayBuffer(32);
    const dv = addon.createDataView(ab, 0, 32);
    const info = addon.getDataViewInfo(dv);
    expect(info.byteLength).toBe(32);
  });

  test('getDataViewInfo returns correct byteOffset', () => {
    const ab = new ArrayBuffer(32);
    const dv = addon.createDataView(ab, 8, 16);
    const info = addon.getDataViewInfo(dv);
    expect(info.byteOffset).toBe(8);
    expect(info.byteLength).toBe(16);
  });

  test('getDataViewInfo on full buffer (offset=0)', () => {
    const ab = new ArrayBuffer(10);
    const dv = addon.createDataView(ab, 0, 10);
    const info = addon.getDataViewInfo(dv);
    expect(info.byteOffset).toBe(0);
    expect(info.byteLength).toBe(10);
  });

  test('isDataView returns true for DataView', () => {
    const ab = new ArrayBuffer(8);
    const dv = addon.createDataView(ab, 0, 8);
    expect(addon.isDataView(dv)).toBe(true);
  });

  test('isDataView returns false for ArrayBuffer', () => {
    const ab = new ArrayBuffer(8);
    expect(addon.isDataView(ab)).toBe(false);
  });

  test('isDataView returns false for plain object', () => {
    expect(addon.isDataView({})).toBe(false);
  });

  test('isDataView returns false for number', () => {
    expect(addon.isDataView(42)).toBe(false);
  });

  test('DataView shares memory with source ArrayBuffer', () => {
    const ab = new ArrayBuffer(4);
    const dv = addon.createDataView(ab, 0, 4);
    // Write through JS DataView
    dv.setUint8(0, 42);
    // Read back through a Uint8Array on the same ArrayBuffer
    const u8 = new Uint8Array(ab);
    expect(u8[0]).toBe(42);
  });

  test('native-created DataView is readable with getUint8', () => {
    const ab = addon.createArrayBuffer(4);
    const dv = addon.createDataView(ab, 0, 4);
    // createArrayBuffer fills with incrementing bytes: 0, 1, 2, 3
    expect(dv.getUint8(0)).toBe(0);
    expect(dv.getUint8(1)).toBe(1);
    expect(dv.getUint8(2)).toBe(2);
    expect(dv.getUint8(3)).toBe(3);
  });

  test('DataView with offset reads correct slice', () => {
    const ab = addon.createArrayBuffer(8);
    // bytes: 0, 1, 2, 3, 4, 5, 6, 7
    const dv = addon.createDataView(ab, 4, 4);
    expect(dv.getUint8(0)).toBe(4);
    expect(dv.getUint8(1)).toBe(5);
  });

  test('JS-created DataView is recognized by isDataView', () => {
    const ab = new ArrayBuffer(4);
    const dv = new DataView(ab);
    expect(addon.isDataView(dv)).toBe(true);
  });
});
