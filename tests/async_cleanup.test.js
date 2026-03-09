'use strict';
const addon = require('../build/index.node');

describe('addAsyncCleanupHook / removeAsyncCleanupHook (Phase 26a)', () => {
  test('addAsyncCleanupHook returns true (hook registered)', () => {
    expect(addon.addAsyncCleanupHook()).toBe(true);
  });

  test('removeAsyncCleanupHook returns true (hook removed)', () => {
    expect(addon.removeAsyncCleanupHook()).toBe(true);
  });

  test('add and remove multiple times without error', () => {
    for (let i = 0; i < 3; i++) {
      expect(addon.addAsyncCleanupHook()).toBe(true);
      expect(addon.removeAsyncCleanupHook()).toBe(true);
    }
  });
});
