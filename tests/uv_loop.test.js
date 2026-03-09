'use strict';
const addon = require('../build/index.node');

describe('getUvEventLoop (Phase 26b)', () => {
  test('returns a non-zero BigInt (valid uv_loop_t pointer)', () => {
    const ptr = addon.getUvEventLoop();
    expect(typeof ptr).toBe('bigint');
    expect(ptr).not.toBe(0n);
  });

  test('returns same pointer on repeated calls', () => {
    const a = addon.getUvEventLoop();
    const b = addon.getUvEventLoop();
    expect(a).toBe(b);
  });
});
