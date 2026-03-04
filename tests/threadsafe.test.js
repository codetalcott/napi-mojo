const addon = require('../build/index.node');

describe('asyncProgress (ThreadsafeFunction)', () => {
  test('calls callback with progress values 0..count-1', async () => {
    const received = [];
    const result = await addon.asyncProgress(3, (value) => {
      received.push(value);
    });
    expect(received).toEqual([0, 1, 2]);
    expect(result).toBe(3);
  });

  test('zero count calls callback zero times', async () => {
    const received = [];
    const result = await addon.asyncProgress(0, (v) => received.push(v));
    expect(received).toEqual([]);
    expect(result).toBe(0);
  });

  test('count of 1 calls callback once', async () => {
    const received = [];
    const result = await addon.asyncProgress(1, (v) => received.push(v));
    expect(received).toEqual([0]);
    expect(result).toBe(1);
  });

  test('returns a thenable (promise)', () => {
    const p = addon.asyncProgress(1, () => {});
    expect(typeof p.then).toBe('function');
    expect(typeof p.catch).toBe('function');
    return p;
  });

  test('does not block the event loop', async () => {
    let timerFired = false;
    setTimeout(() => { timerFired = true; }, 0);
    await addon.asyncProgress(5, () => {});
    await new Promise(resolve => setTimeout(resolve, 10));
    expect(timerFired).toBe(true);
  });

  test('multiple concurrent calls work independently', async () => {
    const results = await Promise.all([
      (async () => {
        const r = [];
        await addon.asyncProgress(2, (v) => r.push(v));
        return r;
      })(),
      (async () => {
        const r = [];
        await addon.asyncProgress(3, (v) => r.push(v));
        return r;
      })(),
    ]);
    expect(results[0]).toEqual([0, 1]);
    expect(results[1]).toEqual([0, 1, 2]);
  });

  test('large count delivers all values in order', async () => {
    const received = [];
    const result = await addon.asyncProgress(100, (v) => received.push(v));
    expect(received.length).toBe(100);
    expect(received[0]).toBe(0);
    expect(received[99]).toBe(99);
    expect(result).toBe(100);
  });

  test('throws on missing arguments', () => {
    expect(() => addon.asyncProgress()).toThrow();
  });
});
