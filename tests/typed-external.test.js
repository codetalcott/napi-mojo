const addon = require('../build/index.node');

describe('typed JsExternal + instance data helpers', () => {
  const newCounter = () => new BigInt64Array(new ArrayBuffer(8));

  test('create_typed + get_typed roundtrip', () => {
    const c = newCounter();
    const h = addon.createTypedPayload(42.5, c.buffer);
    expect(addon.readTypedPayload(h)).toBe(42.5);
  });

  test('get_typed on non-external throws TypeError with context', () => {
    let err;
    try {
      addon.readTypedPayload({ not: 'external' });
    } catch (e) {
      err = e;
    }
    expect(err).toBeDefined();
    expect(err.name).toBe('TypeError');
    expect(err.message).toContain('readTypedPayload');
    expect(err.message).toContain('external');
  });

  test('finalizer runs on GC (requires --expose-gc)', async () => {
    if (typeof global.gc !== 'function') {
      console.warn('skipping: run with `npm run test:gc` to exercise finalizer');
      return;
    }
    const c = newCounter();
    (function () {
      for (let i = 0; i < 500; i++) addon.createTypedPayload(i, c.buffer);
    })();
    global.gc();
    await new Promise((r) => setImmediate(r));
    global.gc();
    await new Promise((r) => setImmediate(r));
    expect(Number(c[0])).toBeGreaterThan(0);
  });

  test('typed instance data roundtrip', () => {
    addon.setTypedInstanceData(7);
    expect(addon.getTypedInstanceData()).toBe(7);
    addon.setTypedInstanceData(99);
    expect(addon.getTypedInstanceData()).toBe(99);
  });
});
