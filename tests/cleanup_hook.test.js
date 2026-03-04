const addon = require('../build/index.node');

describe('Environment Cleanup Hooks', () => {
  test('addCleanupHook does not throw', () => {
    expect(() => addon.addCleanupHook()).not.toThrow();
  });

  test('addCleanupHook returns true', () => {
    expect(addon.addCleanupHook()).toBe(true);
  });

  test('removeCleanupHook does not throw', () => {
    // Add then remove
    addon.addCleanupHook();
    expect(() => addon.removeCleanupHook()).not.toThrow();
  });

  test('removeCleanupHook returns true', () => {
    addon.addCleanupHook();
    expect(addon.removeCleanupHook()).toBe(true);
  });
});
