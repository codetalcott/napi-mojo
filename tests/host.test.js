// tests/host.test.js — Node as a HOST for Mojo.
//
// The inverse of every other suite here: instead of asserting that JS can call
// Mojo, these assert that MOJO can drive Node — require() modules, invoke
// methods with a correct `this`, and iterate without leaking handles.
//
// `ctx` is built by hand below with the same shape the `napi-mojo run`
// bootstrap produces: { require, argv, cwd }. That IS the contract — `require`
// is module-scoped and unreachable from napi_get_global, so the host is always
// handed it rather than scavenging for it.

const addon = require('../build/index.node');
const path = require('path');
const fs = require('fs');
const os = require('os');

const ctx = { require, argv: ['alpha', 'beta'], cwd: process.cwd() };

describe('NodeHost — require', () => {
  test('Mojo can require a Node builtin', () => {
    const m = addon.hostRequire(ctx, 'os');
    expect(typeof m.platform).toBe('function');
    expect(m.platform()).toBe(os.platform());
  });

  test('require returns the identical module object', () => {
    expect(addon.hostRequire(ctx, 'path')).toBe(path);
  });

  test('node: prefixed specifiers resolve', () => {
    expect(addon.hostRequire(ctx, 'node:fs')).toBe(fs);
  });

  test("Node's own MODULE_NOT_FOUND survives the Mojo frame", () => {
    // The addon deliberately throws no replacement error, so the pending JS
    // exception keeps its identity and its code.
    try {
      addon.hostRequire(ctx, 'definitely-not-a-real-module-xyz');
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('MODULE_NOT_FOUND');
    }
  });

  test('a context without require is rejected with a clear message', () => {
    expect(() => addon.hostRequire({}, 'os')).toThrow(/require/);
  });
});

describe('NodeHost — runtime access', () => {
  test('global_object() returns the realm global', () => {
    // NOT `toBe(globalThis)`: Jest runs each suite in a sandboxed realm, so
    // napi_get_global returns the outer global, not this file's. Asserted
    // structurally, the same accommodation tests/global.test.js makes.
    const g = addon.hostGlobal(ctx);
    expect(typeof g).toBe('object');
    expect(typeof g.process).toBe('object');
    expect(typeof g.console).toBe('object');
    expect(typeof g.fetch).toBe('function');
  });

  test('argv() round-trips the bootstrap argv', () => {
    expect(addon.hostArgv(ctx)).toEqual(['alpha', 'beta']);
  });

  test('console_log writes through the host console', () => {
    // Spying on this realm's `console` would miss it — console_log resolves
    // console off the OUTER global (see the realm note above). process.stdout
    // is shared, so intercept the write instead.
    const written = [];
    const real = process.stdout.write;
    process.stdout.write = (chunk, ...rest) => {
      written.push(String(chunk));
      return real.call(process.stdout, chunk, ...rest);
    };
    try {
      addon.hostConsoleLog(ctx, 'from mojo');
    } finally {
      process.stdout.write = real;
    }
    expect(written.join('')).toContain('from mojo');
  });
});

describe('call_method — `this` binding', () => {
  test('binds `this` to the receiver', () => {
    const obj = {
      base: 10,
      add(x) {
        return this.base + x;
      },
    };
    // call1 would pass `undefined` as this and blow up on this.base.
    expect(addon.callMethod(obj, 'add', [5])).toBe(15);
  });

  test('drives a required module end-to-end', () => {
    const p = addon.hostRequire(ctx, 'path');
    expect(addon.callMethod(p, 'join', ['a', 'b', 'c.txt'])).toBe(
      path.join('a', 'b', 'c.txt')
    );
  });

  test('reads a real file through fs.readFileSync', () => {
    const tmp = path.join(os.tmpdir(), `napi-mojo-host-${process.pid}.txt`);
    fs.writeFileSync(tmp, 'payload from disk');
    try {
      const f = addon.hostRequire(ctx, 'fs');
      expect(addon.callMethod(f, 'readFileSync', [tmp, 'utf8'])).toBe(
        'payload from disk'
      );
    } finally {
      fs.unlinkSync(tmp);
    }
  });

  test('zero arguments', () => {
    expect(addon.callMethod({ f: () => 'nullary' }, 'f', [])).toBe('nullary');
  });

  test('a method that throws keeps its error identity', () => {
    const obj = {
      boom() {
        throw new RangeError('method blew up');
      },
    };
    try {
      addon.callMethod(obj, 'boom', []);
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.name).toBe('RangeError');
      expect(e.message).toBe('method blew up');
    }
  });
});

describe('call_n — runtime-length argument lists', () => {
  test('empty list passes a null argv', () => {
    expect(addon.callN(() => 'no args', [])).toBe('no args');
  });

  test.each([1, 2, 3, 8, 32])('%i arguments', (n) => {
    const args = Array.from({ length: n }, (_, i) => i + 1);
    const sum = addon.callN((...xs) => xs.reduce((a, b) => a + b, 0), args);
    expect(sum).toBe(args.reduce((a, b) => a + b, 0));
  });

  test('argument order is preserved', () => {
    expect(addon.callN((...xs) => xs.join('-'), ['a', 'b', 'c'])).toBe('a-b-c');
  });

  test('`this` is undefined, matching call0/1/2', () => {
    // Must be strict mode: the spec substitutes globalThis for an undefined
    // receiver in a sloppy-mode call, which would hide what call_n passed.
    expect(
      addon.callN(function () {
        'use strict';
        return this === undefined;
      }, [])
    ).toBe(true);
  });
});

describe('with_handle_scope — Mojo-driven loops', () => {
  test('runs the body once per iteration', () => {
    let calls = 0;
    expect(addon.scopedCall(5, () => calls++)).toBe(5);
    expect(calls).toBe(5);
  });

  test('passes the index', () => {
    const seen = [];
    addon.scopedCall(4, (i) => seen.push(i));
    expect(seen).toEqual([0, 1, 2, 3]);
  });

  test('a long loop does not exhaust the handle scope', () => {
    // Without a per-iteration scope, each call1 + create_int pins handles to
    // the callback's scope for the whole loop. This is the regression guard.
    let calls = 0;
    expect(
      addon.scopedCall(20000, () => {
        calls++;
        return {};
      })
    ).toBe(20000);
    expect(calls).toBe(20000);
  });
});
