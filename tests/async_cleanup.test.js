'use strict';
const addon = require('../build/index.node');

// addAsyncCleanupHook returns the napi_async_cleanup_hook_handle as an
// External, and removeAsyncCleanupHook removes THAT hook.
//
// It used to return `true` and drop the handle, so remove had nothing to
// remove: it registered a second hook with an identical (function, data)
// pair just to obtain a handle, removed that one, and left the caller's hook
// registered. Node tolerates the duplicate pair; Bun aborts the process on it
// and Deno corrupts the heap at teardown. Both reproduce from a pure C addon,
// so the runtimes gate (scripts/check-runtimes.mjs) is what proves the
// duplicate is gone — these tests pin the API contract that makes it possible.
describe('addAsyncCleanupHook / removeAsyncCleanupHook (Phase 26a)', () => {
  test('addAsyncCleanupHook returns a handle, not a boolean', () => {
    const handle = addon.addAsyncCleanupHook();
    expect(typeof handle).toBe('object');
    expect(handle).not.toBe(null);
    expect(typeof handle).not.toBe('boolean');
    expect(addon.isExternal(handle)).toBe(true);
    expect(addon.removeAsyncCleanupHook(handle)).toBe(true);
  });

  test('removeAsyncCleanupHook removes the handle it is given', () => {
    expect(addon.removeAsyncCleanupHook(addon.addAsyncCleanupHook())).toBe(true);
  });

  test('add and remove multiple times without error', () => {
    for (let i = 0; i < 3; i++) {
      const handle = addon.addAsyncCleanupHook();
      expect(addon.isExternal(handle)).toBe(true);
      expect(addon.removeAsyncCleanupHook(handle)).toBe(true);
    }
  });

  // Deliberately NOT tested here: two hooks live at once. N-API permits it,
  // and the handles now make it usable, but registering the same
  // (function, data) pair twice aborts Bun and corrupts Deno's heap — see the
  // known defects in scripts/check-runtimes.mjs. A test that codified the
  // sequence would have to be excluded from the runtimes gate to pass it.

  test('removeAsyncCleanupHook rejects a non-handle argument', () => {
    expect(() => addon.removeAsyncCleanupHook(42)).toThrow();
    expect(() => addon.removeAsyncCleanupHook('handle')).toThrow();
    expect(() => addon.removeAsyncCleanupHook()).toThrow();
  });
});
