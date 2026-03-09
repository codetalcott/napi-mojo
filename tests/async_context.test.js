const addon = require('../build/index.node');

// makeCallback(fn, arg) — calls fn(arg) via napi_make_callback
// returns the same result as calling fn(arg) directly

test('makeCallback invokes function and returns result', () => {
  const result = addon.makeCallback((x) => x * 2, 21);
  expect(result).toBe(42);
});

test('makeCallback passes string arguments correctly', () => {
  const result = addon.makeCallback((s) => s + '!', 'hello');
  expect(result).toBe('hello!');
});

test('makeCallback with zero-arg function', () => {
  const result = addon.makeCallback0(() => 99);
  expect(result).toBe(99);
});

test('makeCallback with two-arg function', () => {
  const result = addon.makeCallback2((a, b) => a + b, 10, 32);
  expect(result).toBe(42);
});

test('makeCallback propagates AsyncLocalStorage context', () => {
  const { AsyncLocalStorage } = require('node:async_hooks');
  const store = new AsyncLocalStorage();
  let captured = undefined;
  store.run({ value: 'test-context' }, () => {
    // Use makeCallback0 (no args); async context created inside store.run()
    // so napi_async_init captures the ALS context, which make_callback restores
    captured = addon.makeCallback0(() => {
      return store.getStore()?.value ?? 'missing';
    });
  });
  expect(captured).toBe('test-context');
});

// makeCallbackScope — opens/closes a callback scope around a call
test('makeCallbackScope calls function in scope', () => {
  const result = addon.makeCallbackScope((x) => x + 1, 41);
  expect(result).toBe(42);
});
