const addon = require('../build/index.node');

describe('Cancel Async Work', () => {
  test('cancelAsyncWork returns a promise-like object', () => {
    const p = addon.cancelAsyncWork();
    // Cross-realm: instanceof Promise fails in Jest VM sandbox
    expect(typeof p.then).toBe('function');
    expect(typeof p.catch).toBe('function');
    // Suppress unhandled rejection from this test's promise
    p.catch(() => {});
  });

  test('cancelAsyncWork promise settles', async () => {
    // The promise should either resolve or reject depending on
    // whether cancellation happened before the worker started
    try {
      const result = await addon.cancelAsyncWork();
      expect(result).toBe('completed');
    } catch (e) {
      // Rejection value may be a string or an Error object
      const msg = typeof e === 'string' ? e : (e.message || String(e));
      expect(msg.toLowerCase()).toContain('cancel');
    }
  });

  test('cancelAsyncWork does not crash the process', async () => {
    // Run multiple cancellations to stress-test
    const promises = [];
    for (let i = 0; i < 5; i++) {
      promises.push(
        addon.cancelAsyncWork().catch(() => 'cancelled')
      );
    }
    const results = await Promise.all(promises);
    expect(results.length).toBe(5);
  });
});
