const addon = require('../build/index.node');

// Run with: node --expose-gc ./node_modules/.bin/jest tests/finalizer_gc.test.js
// Or:       npm run test:gc

const gc = global.gc;

const describeGC = gc ? describe : describe.skip;

const drainGC = async () => {
  // Two gc+microtask rounds: external/wrap finalizers run as second-pass
  // callbacks on the event loop, so a single synchronous gc() can return
  // before any finalizer has executed.
  gc();
  await new Promise((r) => setImmediate(r));
  gc();
  await new Promise((r) => setImmediate(r));
};

describeGC('Finalizer execution (requires --expose-gc)', () => {
  // The one test here that proves finalizers actually RUN, not merely that
  // collection doesn't crash: each TypedPayload finalizer increments the
  // Int64 counter inside the caller-provided ArrayBuffer (and holds a ref on
  // that buffer so the increment can't scribble on freed memory — the exact
  // UAF this addon shipped once). A finalizer that silently never fires is a
  // leak, and every other test in this file would still pass.
  test('finalizers observably execute on GC', async () => {
    const counter = new BigInt64Array(new ArrayBuffer(8));
    (function scope() {
      for (let i = 0; i < 200; i++) addon.createTypedPayload(i, counter.buffer);
    })();
    await drainGC();
    expect(Number(counter[0])).toBeGreaterThan(0);
  });

  // The remaining tests are crash canaries: their real assertion is "the
  // process survived collection AND the addon still functions afterwards"
  // (heap corruption from a bad finalizer typically surfaces on the next
  // allocation, which is why each test does real work after gc()).
  test('Counter instances can be collected; class machinery survives', async () => {
    for (let i = 0; i < 100; i++) {
      new addon.Counter(i);
    }
    await drainGC();
    const c = new addon.Counter(7);
    c.increment();
    expect(c.value).toBe(8);
  });

  test('External values can be collected; externals still work after', async () => {
    for (let i = 0; i < 100; i++) {
      addon.createExternal(i, i * 2);
    }
    await drainGC();
    const ext = addon.createExternal(1.5, 2.5);
    const data = addon.getExternalData(ext);
    expect(data.x).toBeCloseTo(1.5);
    expect(data.y).toBeCloseTo(2.5);
  });

  test('External ArrayBuffers can be collected; allocation still works after', async () => {
    for (let i = 0; i < 50; i++) {
      addon.createExternalArrayBuffer(1024);
    }
    await drainGC();
    const ab = addon.createExternalArrayBuffer(2048);
    expect(ab.byteLength).toBe(2048);
  });

  test('attachFinalizer objects can be collected; attaching still works after', async () => {
    for (let i = 0; i < 100; i++) {
      addon.attachFinalizer({ id: i });
    }
    await drainGC();
    const obj = addon.attachFinalizer({ id: 'after-gc' });
    expect(obj.id).toBe('after-gc');
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
