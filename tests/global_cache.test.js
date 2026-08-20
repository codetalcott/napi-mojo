const addon = require('../build/index.node');

describe('global bootstrap-symbol cache', () => {
  // napi/global_cache.mojo serves napi_get_cb_info from a data-segment slot
  // (pop.global_alloc + @no_inline) instead of running dlopen(NULL)+dlsym on
  // every single callback. That was ~346 ns/call and was essentially the whole
  // measured gap against napi-rs.
  //
  // The optimisation degrades SILENTLY: if a toolchain change stops honouring
  // the @no_inline it relies on, each call site gets its own zeroed slot, every
  // call re-resolves the symbol, and everything still WORKS — just ~346 ns/call
  // slower, with no test failing. This file is the alarm for that, in the same
  // spirit as tests/runtime.test.js guarding parallelize_safe's silent
  // sequential fallback.

  test('the bootstrap symbol is served from the global slot', () => {
    // Reaching any export already required the bootstrap, so a healthy build
    // has populated the slot by the time this runs.
    expect(addon.globalCacheActive()).toBe(true);
  });

  test('it stays active across many separate callback entries', () => {
    for (let i = 0; i < 1000; i++) addon.hello();
    expect(addon.globalCacheActive()).toBe(true);
  });

  test('callbacks still return correct values with the cache live', () => {
    // The failure mode to rule out is a bad reinterpret of the cached address:
    // calling the wrong thing would corrupt or crash rather than return these.
    expect(addon.hello()).toBe('Hello from Mojo!');
    expect(addon.add(2, 3)).toBe(5);
    expect(addon.greet('world')).toBe('Hello, world!');
    expect(addon.getNull()).toBeNull();
    expect(addon.makeGreeting()).toEqual({ message: 'Hello!' });
  });

  test('argument extraction through the cached bootstrap is correct', () => {
    // get_cb_info is what reads argc/argv, so an off-by-one in the cached path
    // would show up here rather than in the zero-arg cases above.
    expect(addon.sumArgs(1, 2, 3, 4, 5)).toBe(15);
    expect(addon.sumArgs()).toBe(0);
    expect(addon.addInts(7, 8)).toBe(15);
  });
});
