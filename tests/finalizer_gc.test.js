const addon = require('../build/index.node');

// Run with: node --expose-gc ./node_modules/.bin/jest tests/finalizer_gc.test.js
// Or:       npm run test:gc

const gc = global.gc;

const describeGC = gc ? describe : describe.skip;

describeGC('Finalizer execution (requires --expose-gc)', () => {
  test('Counter instances can be collected without crash', () => {
    for (let i = 0; i < 100; i++) {
      new addon.Counter(i);
    }
    gc();
    // If counter_finalize double-frees or corrupts, this crashes
    expect(true).toBe(true);
  });

  test('External values can be collected without crash', () => {
    for (let i = 0; i < 100; i++) {
      addon.createExternal(i, i * 2);
    }
    gc();
    expect(true).toBe(true);
  });

  test('External ArrayBuffers can be collected without crash', () => {
    for (let i = 0; i < 50; i++) {
      addon.createExternalArrayBuffer(1024);
    }
    gc();
    expect(true).toBe(true);
  });

  test('attachFinalizer objects can be collected without crash', () => {
    for (let i = 0; i < 100; i++) {
      addon.attachFinalizer({ id: i });
    }
    gc();
    expect(true).toBe(true);
  });

  test('Counter values remain valid while referenced', () => {
    const c = new addon.Counter(42);
    gc();
    expect(c.value).toBe(42);
    c.increment();
    expect(c.value).toBe(43);
  });

  test('External data remains valid while referenced', () => {
    const ext = addon.createExternal(3.14, 2.71);
    gc();
    const data = addon.getExternalData(ext);
    expect(data.x).toBeCloseTo(3.14);
    expect(data.y).toBeCloseTo(2.71);
  });
});
