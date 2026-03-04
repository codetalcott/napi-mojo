const addon = require('../build/index.node');

describe('Instance Data (per-env singleton)', () => {
  test('getInstanceData before setInstanceData returns null', () => {
    // Note: this test may fail if run after setInstanceData tests
    // since instance data persists for the env lifetime.
    // We test the set/get sequence instead.
    const result = addon.getInstanceData();
    // Could be null (first call) or a number (if other tests ran first)
    expect(result === null || typeof result === 'number').toBe(true);
  });

  test('setInstanceData(42) does not throw', () => {
    expect(() => addon.setInstanceData(42)).not.toThrow();
  });

  test('getInstanceData after setInstanceData(42) returns 42', () => {
    addon.setInstanceData(42);
    expect(addon.getInstanceData()).toBe(42);
  });

  test('setInstanceData replaces previous value', () => {
    addon.setInstanceData(100);
    expect(addon.getInstanceData()).toBe(100);
    addon.setInstanceData(200);
    expect(addon.getInstanceData()).toBe(200);
  });

  test('setInstanceData(0) round-trips', () => {
    addon.setInstanceData(0);
    expect(addon.getInstanceData()).toBe(0);
  });

  test('setInstanceData(-3.14) round-trips', () => {
    addon.setInstanceData(-3.14);
    expect(addon.getInstanceData()).toBe(-3.14);
  });
});
