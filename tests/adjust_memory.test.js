const addon = require('../build/index.node');

describe('adjustExternalMemory', () => {
  test('returns a number', () => {
    const result = addon.adjustExternalMemory(1024);
    expect(typeof result).toBe('number');
  });

  test('accepts positive values', () => {
    const result = addon.adjustExternalMemory(4096);
    expect(result).toBeGreaterThanOrEqual(0);
  });

  test('accepts negative values', () => {
    // First allocate, then free
    addon.adjustExternalMemory(8192);
    const result = addon.adjustExternalMemory(-8192);
    expect(typeof result).toBe('number');
  });

  test('accepts zero', () => {
    const result = addon.adjustExternalMemory(0);
    expect(typeof result).toBe('number');
  });
});
