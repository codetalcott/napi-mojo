// Guards parallelize_safe's otherwise-invisible failure modes.
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
// 3. THE ADDON IS UNLOADED UNDER THE RUNNING RUNTIME -> a crash as a Worker
//    exits, in a process where nothing else loaded the addon. See the last
//    describe block.
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

// Node unloads a Worker's addons with its environment, and parallelize_safe
// leaves the async runtime running: its threads outlive the call, and the
// image that started them. The Jest process holds this file's own `addon`,
// which keeps everything loaded, so the case runs in a fresh process whose
// main thread never loads the addon: each Worker holds the only reference,
// and its exit unloads index.node.
//
// On Linux the runtime's libraries are linked NODELETE, so they stay mapped,
// its threads park, and the next load reuses them. Mutation-checked there:
// with NODELETE cleared on copies of libKGENCompilerRTShared,
// libAsyncRTMojoBindings, libAsyncRTRuntimeGlobals and libMSupportGlobals put
// first on LD_LIBRARY_PATH, the process dies of SIGSEGV as the first Worker
// exits, whether it ends or is terminated, and unpatched copies on the same
// path run clean. Mach-O has no NODELETE, so the macOS leg is the evidence
// for macOS.
describe('parallelize_safe in a Worker that alone loads the addon', () => {
  const { spawnSync } = require('child_process');
  const path = require('path');
  const ADDON = path.join(__dirname, '..', 'build', 'index.node');

  const WORKER = `
    const { parentPort, workerData } = require('worker_threads');
    const addon = require(workerData.addon);
    const n = 100000;
    const out = addon.parallelSquares(n, 2);
    let wrong = 0;
    for (let i = 0; i < n; i++) if (out[i] !== i * i * 2) wrong++;
    parentPort.postMessage({ init: addon.asyncRuntimeInitOk(), wrong });
    if (workerData.stay) setInterval(() => {}, 1000);
  `;

  // Three Workers in turn, each loading the addon, dispatching and unloading
  // it. With `terminate`, each stays alive until the main thread terminates
  // it. The thread count is read once each Worker has gone (Linux; -1
  // elsewhere).
  const script = (terminate) => `
    const { Worker } = require('worker_threads');
    const fs = require('fs');
    const threads = () =>
      fs.existsSync('/proc/self/task') ? fs.readdirSync('/proc/self/task').length : -1;
    const once = () => new Promise((resolve, reject) => {
      const w = new Worker(${JSON.stringify(WORKER)}, {
        eval: true,
        workerData: { addon: ${JSON.stringify(ADDON)}, stay: ${terminate} },
      });
      let result = {};
      w.on('message', (m) => {
        result = m;
        if (${terminate}) w.terminate();
      });
      w.on('error', reject);
      w.on('exit', (code) => resolve({ ...result, code }));
    });
    (async () => {
      const runs = [];
      for (let i = 0; i < 3; i++) {
        const run = await once();
        await new Promise((r) => setTimeout(r, 200));
        runs.push({ ...run, threads: threads() });
      }
      console.log(JSON.stringify(runs));
    })();
  `;

  const runWorkers = (terminate) => {
    const res = spawnSync(process.execPath, ['-e', script(terminate)], {
      encoding: 'utf8',
      timeout: 30000,
    });
    // toEqual, not toMatchObject, so a failure prints how the child died.
    expect({ status: res.status, signal: res.signal, stderr: res.stderr }).toEqual({
      status: 0,
      signal: null,
      stderr: expect.any(String),
    });
    return JSON.parse(res.stdout);
  };

  const expectRuns = (runs, exitCode) => {
    expect(runs.map(({ init, wrong, code }) => ({ init, wrong, code }))).toEqual(
      Array(3).fill({ init: true, wrong: 0, code: exitCode }),
    );
    // Reused, not started again beside the first runtime's parked threads.
    expect(runs[2].threads).toBe(runs[0].threads);
  };

  test('a Worker that ends unloads the addon, and the next load reuses the runtime', () => {
    expectRuns(runWorkers(false), 0);
  });

  test('a terminated Worker unloads it the same way', () => {
    expectRuns(runWorkers(true), 1);
  });
});
