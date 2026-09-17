// Guards parallelize_safe's two otherwise-invisible failure modes.
//
// 1. INIT FAILS -> the work silently runs SEQUENTIALLY. Results stay correct,
//    the build stays green, every other test stays green, and all thread
//    parallelism is gone. dev2026072306 did exactly that, by renaming the
//    private KGEN symbol the init used to resolve by hand, and it went
//    unnoticed until someone read the source. asyncRuntimeInitOk() exports
//    the init result so that is assertable. (Since Mojo 1.0.0 the init
//    delegates to the official std.runtime.initialize_runtime(), so a rename
//    is no longer the likely cause — but "init failed" is still unobservable
//    from the outside without this.)
//
// 2. THE WORK RUNS WITH BROKEN CAPTURES -> garbage results, and nothing
//    checked the results. Mojo 1.1.0 made this real twice over: a legacy
//    closure parameter spelled bare `capturing` reads a DEAD STACK SLOT with
//    no warning and no error, and MAX 26.6 moved parallelize() to a unified
//    closure argument, forcing parallelize_safe to wrap `func` in a closure
//    of its own. Before parallelSquares existed, parallelize_safe was not
//    instantiated anywhere in the addon graph at all — so Mojo never
//    elaborated its body and it could fail to COMPILE with build.sh and the
//    whole suite green. That is what the 1.1.0 bump hit.
//
// Mutation-checked, which is the only thing that makes a guard evidence:
// reverting runtime.mojo to bare `capturing` and rebuilding makes
// parallelSquares SIGSEGV (node exits 139) rather than return wrong numbers —
// the dead slot holds a garbage pointer, not a stale value. So expect that
// regression to surface as a CRASHED JEST WORKER for this file, not as a
// clean assertion diff. Either way it is red.
//
// Deliberately NOT a parallelism assertion: the sequential fallback computes
// the same values by design, so only asyncRuntimeInitOk() can say which path
// ran. A timing-based check would be flaky and would not be worth it.
//
// Runs on both CI matrix OSes, which also settles whether any future change
// here is Darwin-only.

const addon = require('../build/index.node');

describe('async runtime', () => {
  test('asyncRuntimeInitOk() returns a boolean', () => {
    expect(typeof addon.asyncRuntimeInitOk()).toBe('boolean');
  });

  test('async runtime initializes, so parallelize_safe() dispatches to threads', () => {
    // A false here is not a crash — it means parallel work silently became
    // sequential. Check the symbol name in src/napi/framework/runtime.mojo
    // against `dyld_info -exports` (macOS) / `nm -D` (Linux) on
    // libKGENCompilerRTShared; `nm -gU` shows nothing useful there.
    expect(addon.asyncRuntimeInitOk()).toBe(true);
  });

  test('init is idempotent across repeated calls', () => {
    for (let i = 0; i < 5; i++) {
      expect(addon.asyncRuntimeInitOk()).toBe(true);
    }
  });
});

describe('parallelize_safe computes correct results', () => {
  // Pre-filled into every slot by the addon before the parallel work runs, so
  // "the work never touched index i" is distinguishable from "it computed
  // index i wrongly". No legitimate result can collide with it.
  const UNWRITTEN = -123456789.5;

  const expected = (n, scale) => Array.from({ length: n }, (_, i) => i * i * scale);

  // Cross-realm safe, the same helper tests/typedarray.test.js uses:
  // `instanceof Float64Array` fails inside Jest's sandboxed VM even when the
  // value IS one, because the realms differ (the failure reads absurdly —
  // "Expected constructor: Float64Array, Received constructor: Float64Array").
  const typedArrayName = (v) => Object.prototype.toString.call(v).slice(8, -1);

  test('returns a Float64Array of the requested length', () => {
    const out = addon.parallelSquares(8, 1);
    expect(typedArrayName(out)).toBe('Float64Array');
    expect(out.length).toBe(8);
  });

  test('every element reflects both captured values', () => {
    // Each element depends on the captured output pointer AND the captured
    // `scale`, so a closure reading a dead or stale slot cannot produce this.
    expect(Array.from(addon.parallelSquares(8, 3))).toEqual(expected(8, 3));
  });

  test('a non-integer scale rules out an accidentally-correct integer capture', () => {
    expect(Array.from(addon.parallelSquares(16, 0.5))).toEqual(expected(16, 0.5));
  });

  test('a negative scale is carried through', () => {
    expect(Array.from(addon.parallelSquares(16, -2))).toEqual(expected(16, -2));
  });

  test('no index is left unwritten, well above the dispatch threshold', () => {
    // parallelize_safe's docstring puts the thread-dispatch crossover at
    // n >= ~64, so 4096 is comfortably on the parallel path where a missed
    // or double-assigned index would show up.
    const n = 4096;
    const out = addon.parallelSquares(n, 0.25);
    const unwritten = [];
    const wrong = [];
    for (let i = 0; i < n; i++) {
      if (out[i] === UNWRITTEN) unwritten.push(i);
      else if (out[i] !== i * i * 0.25) wrong.push(i);
    }
    expect({ unwritten: unwritten.slice(0, 8), wrong: wrong.slice(0, 8) }).toEqual({
      unwritten: [],
      wrong: [],
    });
  });

  test('results are stable across repeated dispatches', () => {
    // A capture that survives the first call but not later ones, or worker
    // state leaking between dispatches, shows up here and not above.
    const first = Array.from(addon.parallelSquares(256, 1.5));
    for (let i = 0; i < 5; i++) {
      expect(Array.from(addon.parallelSquares(256, 1.5))).toEqual(first);
    }
    expect(first).toEqual(expected(256, 1.5));
  });

  test('n = 1 works (smallest dispatch)', () => {
    expect(Array.from(addon.parallelSquares(1, 7))).toEqual([0]);
  });

  test('out-of-range n is a RangeError, not an allocation', () => {
    // A diagnostic export must not be a way to ask the addon for an
    // arbitrarily large allocation.
    for (const n of [0, -1, 4194305]) {
      expect(() => addon.parallelSquares(n, 1)).toThrow(/between 1 and 4194304/);
    }
  });

  test('a non-number argument throws rather than reinterpreting', () => {
    expect(() => addon.parallelSquares('8', 1)).toThrow();
    expect(() => addon.parallelSquares(8, 'x')).toThrow();
  });
});
