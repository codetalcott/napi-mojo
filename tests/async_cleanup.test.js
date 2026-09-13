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

  // napi_remove_async_cleanup_hook FREES the handle, so the two misuses below
  // used to reach freed or foreign memory and kill the process (SIGSEGV, exit
  // 139). Each runs in a child process: if the guard regresses, the failure
  // is a readable exit status here instead of a crashed Jest worker.
  const runIsolated = (body) => {
    const { spawnSync } = require('child_process');
    const script =
      `const addon = require(${JSON.stringify(require.resolve('../build/index.node'))});\n` +
      `const threw = (fn) => { try { fn(); return 'no-throw'; } catch (e) { return e.message; } };\n` +
      body;
    const r = spawnSync(process.execPath, ['-e', script], { encoding: 'utf8' });
    return { status: r.status, signal: r.signal, stdout: r.stdout.trim(), stderr: r.stderr };
  };

  test('removing the same handle twice throws instead of freeing it twice', () => {
    const r = runIsolated(`
      const h = addon.addAsyncCleanupHook();
      addon.removeAsyncCleanupHook(h);
      console.log(threw(() => addon.removeAsyncCleanupHook(h)));
    `);
    expect({ status: r.status, signal: r.signal }).toEqual({ status: 0, signal: null });
    expect(r.stdout).toMatch(/already removed/);
  });

  test('an External that addAsyncCleanupHook did not create is rejected', () => {
    const r = runIsolated(`
      console.log(threw(() => addon.removeAsyncCleanupHook(addon.createExternal(1, 2))));
    `);
    expect({ status: r.status, signal: r.signal }).toEqual({ status: 0, signal: null });
    expect(r.stdout).toMatch(/pass the handle returned by addAsyncCleanupHook/);
  });
});
