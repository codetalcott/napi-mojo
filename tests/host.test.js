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

  test('console_error writes through the host console', () => {
    // Same realm accommodation as console_log above: intercept the shared
    // stream rather than spying on this realm's `console`.
    const written = [];
    const real = process.stderr.write;
    process.stderr.write = (chunk, ...rest) => {
      written.push(String(chunk));
      return real.call(process.stderr, chunk, ...rest);
    };
    try {
      addon.hostConsoleError(ctx, 'bad news from mojo');
    } finally {
      process.stderr.write = real;
    }
    expect(written.join('')).toContain('bad news from mojo');
  });

  test('console_error goes to stderr, not stdout', () => {
    // The whole point of the method: diagnostics must not pollute a program
    // whose stdout is being piped. console_log's test would still pass if
    // console_error were wired to "log" by mistake, so assert the split.
    const out = [];
    const realOut = process.stdout.write;
    process.stdout.write = (chunk, ...rest) => {
      out.push(String(chunk));
      return realOut.call(process.stdout, chunk, ...rest);
    };
    try {
      addon.hostConsoleError(ctx, 'stderr-only-marker');
    } finally {
      process.stdout.write = realOut;
    }
    expect(out.join('')).not.toContain('stderr-only-marker');
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

describe('continuation passing — JsPromise.on_settled', () => {
  // Mojo code cannot wait for a promise: it runs on the JS thread, and a
  // promise settles only after the calling callback returns. The supported
  // shape is a continuation. thenDouble / thenScaled / deferredRequire are
  // built on JsPromise.on_settled and call onResult node-style:
  // onResult(null, value) on success, onResult(reason) on rejection.
  const settle = (fn) => new Promise((resolve) => fn((err, v) => resolve({ err, v })));

  test('a Mojo continuation fires on a later tick', async () => {
    const { err, v } = await settle((cb) => addon.thenDouble(Promise.resolve(21), cb));
    expect(err).toBeNull();
    expect(v).toBe(42);
  });

  test('the continuation really is deferred, not synchronous', () => {
    let fired = false;
    addon.thenDouble(Promise.resolve(1), () => {
      fired = true;
    });
    // Still on the same tick: .then() callbacks cannot have run yet.
    expect(fired).toBe(false);
  });

  test('several continuations in flight stay independent', async () => {
    const results = await Promise.all(
      [1, 2, 3, 4, 5].map((n) => settle((cb) => addon.thenDouble(Promise.resolve(n), cb)))
    );
    expect(results.map((r) => r.v)).toEqual([2, 4, 6, 8, 10]);
  });

  test('a continuation on an already-settled promise still defers', async () => {
    const p = Promise.resolve(50);
    await null; // let p settle fully
    const { v } = await settle((cb) => addon.thenDouble(p, cb));
    expect(v).toBe(100);
  });

  test('a non-promise value is awaited, like `await`', async () => {
    expect((await settle((cb) => addon.thenDouble(21, cb))).v).toBe(42);
    const thenable = { then: (res) => res(4) };
    expect((await settle((cb) => addon.thenDouble(thenable, cb))).v).toBe(8);
  });

  test('returns the promise .then() made, which settles with onResult', async () => {
    const derived = addon.thenDouble(Promise.resolve(3), (err, v) => `got ${v}`);
    expect(typeof derived.then).toBe('function');
    await expect(derived).resolves.toBe('got 6');
  });

  test('a rejection reaches onResult with its identity, and is handled', async () => {
    // The first version attached only onFulfilled, so a rejected source
    // promise crashed the process with an unhandled rejection and onResult
    // never ran. Resolving (not rejecting) proves the rejection was consumed.
    const boom = new Error('boom');
    await expect(addon.thenDouble(Promise.reject(boom), (err) => err)).resolves.toBe(boom);
    // Any value can be a rejection reason, primitives included.
    await expect(addon.thenDouble(Promise.reject(7), (err) => err)).resolves.toBe(7);
  });

  test('a Mojo-side failure rejects the returned promise instead of vanishing', async () => {
    // The first version swallowed it (`except: pass`): onResult never ran and
    // nothing, anywhere, reported why.
    let called = false;
    const derived = addon.thenDouble(Promise.resolve('not a number'), () => {
      called = true;
    });
    await expect(derived).rejects.toThrow(/napi_number_expected/);
    expect(called).toBe(false);
  });

  test('an exception thrown by onResult keeps its identity', async () => {
    const thrown = new Error('from onResult');
    const derived = addon.thenDouble(Promise.resolve(1), () => {
      throw thrown;
    });
    await expect(derived).rejects.toBe(thrown);
  });

  test('native state reaches the continuation through `data`', async () => {
    const counter = new ArrayBuffer(8);
    const { err, v } = await settle((cb) => addon.thenScaled(Promise.resolve(5), 3, counter, cb));
    expect(err).toBeNull();
    expect(v).toBe(15);
  });

  test('require survives into a later tick as a capture', async () => {
    // The persistence story: a host program can still reach npm after the
    // call that received `ctx` has returned. `require` travels as a bound
    // argument of the continuation, not in a napi_ref.
    const { err, v } = await settle((cb) => addon.deferredRequire(ctx, cb));
    expect(err).toBeNull();
    expect(v).toBe(path.sep);
  });

  test('deferred require rejects a context without require', () => {
    expect(() => addon.deferredRequire({}, () => {})).toThrow(/require/);
  });

  test('many continuations all complete', async () => {
    const N = 2000;
    const results = await Promise.all(
      Array.from({ length: N }, (_, i) => settle((cb) => addon.thenDouble(Promise.resolve(i), cb)))
    );
    expect(results).toHaveLength(N);
    expect(results[N - 1].v).toBe((N - 1) * 2);
  });
});
