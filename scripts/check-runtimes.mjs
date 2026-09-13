#!/usr/bin/env node
/**
 * check-runtimes.mjs — does the addon behave the same on every JS runtime
 * that implements N-API?
 *
 * Node is not the only N-API host: Deno and Bun implement it too, and an
 * addon that loads under all three reaches a wider audience for free. That is
 * only a claim worth making if something checks it, and `npm test` cannot —
 * it runs Node.
 *
 * WHY A CHILD PROCESS PER SCENARIO, rather than assertions in one process:
 * every defect this gate has found so far was a PROCESS-level event, not a
 * wrong return value. Bun aborts on a duplicate async cleanup hook; Deno
 * reports a glibc double free at teardown, AFTER the last line of user code
 * has run and with a zero exit code on some paths. A gate that only compared
 * return values inside one process would have seen neither. So each scenario
 * runs as its own child, and stderr and the exit code are part of the result.
 *
 * WHAT IT ASSERTS
 *   1. surface  — every scenario produces the same output on every runtime as
 *                 it does on Node, and no runtime reports a heap error.
 *   2. defects  — every entry in KNOWN_DEFECTS still reproduces. A defect that
 *                 has been fixed upstream FAILS the gate, so the allowance
 *                 cannot outlive the bug it documents. Same ratchet as
 *                 KNOWN_UNDOCUMENTABLE in check-docstring-coverage.mjs.
 *
 * Usage:
 *   node scripts/check-runtimes.mjs                 # gate; Node + whatever is installed
 *   node scripts/check-runtimes.mjs --addon <path>  # default: build/index.node
 *   node scripts/check-runtimes.mjs --require-all   # fail if a runtime is missing
 *   node scripts/check-runtimes.mjs --json
 */

import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// ---------------------------------------------------------------------------
// Runtimes. Node is the control: every other runtime is compared against it,
// so it is never itself "wrong" — a Node-side change shows up as every other
// runtime disagreeing at once, which is the honest signal.
// ---------------------------------------------------------------------------
const RUNTIMES = [
  { name: 'node', cmd: 'node', args: (f) => [f], control: true },
  // Deno needs the permission flag to dlopen a native addon; --unstable-* is
  // not needed for require() of a .node in Deno 2.x.
  { name: 'deno', cmd: 'deno', args: (f) => ['run', '--allow-all', f] },
  { name: 'bun', cmd: 'bun', args: (f) => [f] },
];

// ---------------------------------------------------------------------------
// Scenarios. Each is a CJS program body run with `addon` already required.
// Print one line per assertion: the gate compares the text, not the values, so
// a scenario can cover as much as it likes as long as its output is stable
// across runtimes. Anything genuinely runtime-specific (napi version, pointer
// values, Node version) must NOT be printed here — put it in INFO instead.
// ---------------------------------------------------------------------------
const SCENARIOS = [
  ['basics', `
    log('hello', addon.hello());
    log('add', addon.add(2, 3));
    log('greet', addon.greet('world'));
    log('typecheck', tryCatch(() => addon.greet(42)));
    log('typeError', tryCatch(() => addon.throwTypeError()));
    log('throwValue', tryCatch(() => addon.throwValue({ code: 7 })));
    log('coerce', addon.coerceToString(42), addon.coerceToNumber('8'));
  `],
  ['callbacks', `
    log('callFunction', addon.callFunction((n) => n * 10, 4));
    log('mapArray', JSON.stringify(addon.mapArray([1, 2, 3], (n) => n + 1)));
    log('sumArgs', addon.sumArgs(1, 2, 3, 4));
    log('createAdder', addon.createAdder(10)(5));
    log('makeCallback', addon.makeCallback((n) => n + 1, 1));
    log('makeCallbackScope', addon.makeCallbackScope((x) => x + 1, 41));
  `],
  ['async', `
    (async () => {
      log('resolveWith', await addon.resolveWith(41));
      log('rejectWith', await addon.rejectWith('nope').then(() => 'BAD', (e) => e.message));
      log('asyncDouble', await addon.asyncDouble(21));
      log('asyncSum', await addon.asyncSum(2, 40));
      log('asyncLabel', await addon.asyncLabel('hi'));
      log('cancel', await addon.cancelAsyncWork().then(() => 'BAD', (e) => e.message));
      const seen = [];
      await addon.asyncProgress(5, (i) => seen.push(i));
      log('tsfnTicks', seen.length);
    })();
  `],
  ['classes', `
    const c = new addon.Counter(0); c.increment(); c.increment();
    log('counter', c.value);
    log('static', addon.Counter.isCounter(c));
    log('animal', new addon.Animal('Cat').speak());
    const d = new addon.Dog('Rex', 'Labrador');
    log('dog', d.speak(), d.breed);
    const p = new addon.ExamplePoint(3, 4);
    log('point', p.x, p.y);
    const t = new addon.Tally('counter', 5);
    log('tally', typeof t);
    // A method borrowed onto a foreign wrapped instance must throw rather
    // than reinterpret the wrong struct. The error TYPE differs by runtime
    // (Bun reports Error where Node and Deno report TypeError), so assert
    // only that it threw — the memory-safety property, not the wrapper.
    log('typeTagGuard', tryCatch(() => addon.Counter.prototype.increment.call(new addon.Animal('X'))) !== 'no-throw');
  `],
  ['binary', `
    log('arrayBuffer', addon.arrayBufferLength(addon.createArrayBuffer(16)));
    log('buffer', addon.sumBuffer(addon.createBuffer(4)));
    const f = new Float64Array([1, 2, 3]); addon.doubleFloat64Array(f);
    log('typedArray', f.join(','));
    log('dataView', addon.isDataView(addon.createDataView(new ArrayBuffer(8), 0, 8)));
    log('externalAB', addon.createExternalArrayBuffer(8).byteLength);
    const ab = addon.createArrayBuffer(8); addon.detachArrayBuffer(ab);
    log('detach', addon.isDetachedArrayBuffer(ab));
  `],
  ['values', `
    log('bigint', String(addon.addBigInts(1n, 2n)));
    log('bigintWords', String(addon.bigIntFromWords(0, [0, 1])));
    log('date', addon.getDateValue(addon.createDate(1700000000000)));
    log('symbol', typeof addon.createSymbol('s'));
    log('strictEquals', addon.strictEquals(1, 1), addon.strictEquals(1, '1'));
    // Primitives in a napi_ref need N-API v10. Bun answers 9 to
    // napi_get_version and supports them anyway, which is why this gate
    // tests the behaviour and never the version number.
    log('refNumber', addon.testRef());
    log('refString', addon.testRefString('hello'));
    log('refObject', typeof addon.testRefObject());
  `],
  ['env', `
    log('external', typeof addon.getExternalData(addon.createExternal(1.5, 2.5)));
    log('isExternal', addon.isExternal(addon.createExternal(1, 2)));
    addon.setInstanceData(7);
    log('instanceData', addon.getInstanceData());
    addon.setTypedInstanceData(3, 'y');
    log('typedInstanceData', addon.getTypedInstanceData());
    addon.addCleanupHook();
    log('cleanupHook', addon.removeCleanupHook());
    log('runScript', addon.runScript('1+1'));
    log('asyncRuntimeInit', addon.asyncRuntimeInitOk());
    log('globalCache', addon.globalCacheActive());
  `],
  // The regression guard for the defect that prompted this gate. Adding a
  // hook and removing it by its own handle registers exactly one
  // (function, data) pair and leaves none live at teardown.
  ['asyncCleanupHook', `
    const h = addon.addAsyncCleanupHook();
    log('isHandle', addon.isExternal(h));
    log('removed', addon.removeAsyncCleanupHook(h));
    log('rejectsNonHandle', tryCatch(() => addon.removeAsyncCleanupHook(42)) !== 'no-throw');
    // napi_remove_async_cleanup_hook frees the handle: a second remove, or a
    // foreign External, used to reach freed/arbitrary memory and crash.
    log('rejectsDoubleRemove', tryCatch(() => addon.removeAsyncCleanupHook(h)) !== 'no-throw');
    log('rejectsForeignExternal', tryCatch(() => addon.removeAsyncCleanupHook(addon.createExternal(1, 2))) !== 'no-throw');
  `],
  ['host', `
    log('callN', addon.callN((a, b, c) => a + b + c, [1, 2, 3]));
    log('callMethod', addon.callMethod({ v: 3, get() { return this.v; } }, 'get', []));
    let n = 0; addon.scopedCall(2000, () => n++);
    log('scopedCall', n);
    log('hostGlobal', typeof addon.hostGlobal({ require, argv: [], cwd: '.' }));
  `],
];

// ---------------------------------------------------------------------------
// Known defects in third-party runtimes, each with a scenario that must still
// reproduce it. Reproducing means: the child dies, or its stderr matches.
//
// These are NOT napi-mojo bugs — each is reproducible from a pure C N-API
// addon — docs/plan-distribution.md has the analysis and the recipe.
// They are recorded so the framework's own code never relies on the shapes
// that trip them, and so the entry disappears when the runtime fixes it.
//
// REMOVING AN ENTRY IS THE POINT. When a runtime ships a fix this gate turns
// red with "no longer reproduces" — delete the entry, and if the framework
// avoided a shape only because of it, revisit that too.
// ---------------------------------------------------------------------------
const KNOWN_DEFECTS = [
  {
    id: 'bun-duplicate-async-cleanup-hook',
    runtime: 'bun',
    // Two hooks with an identical (function, data) pair. N-API permits it;
    // Bun asserts the pair is unique and aborts the process.
    body: `
      addon.addAsyncCleanupHook();
      addon.addAsyncCleanupHook();
      log('survived', true);
    `,
    expect: /duplicate async NAPI environment cleanup hook|panic|Aborted/i,
    note: 'Bun aborts on a second async cleanup hook with the same (fn, data) pair',
  },
  {
    id: 'deno-async-cleanup-hook-double-free',
    runtime: 'deno',
    // One hook, left registered so it runs at teardown and signals completion
    // with napi_remove_async_cleanup_hook — the documented contract. Deno
    // frees the handle a second time.
    body: `
      addon.addAsyncCleanupHook();
      log('registered', true);
    `,
    expect: /double free|corruption/i,
    note: 'Deno double-frees an async cleanup hook handle at env teardown',
  },
];

// ---------------------------------------------------------------------------

const PRELUDE = (addonPath) => `
'use strict';
const addon = require(${JSON.stringify(addonPath)});
const out = [];
function log(...parts) { console.log(parts.join(' ')); }
function tryCatch(fn) { try { fn(); return 'no-throw'; } catch (e) { return 'threw'; } }
`;

function runScenario(runtime, addonPath, body, dir, name) {
  const file = join(dir, `${runtime.name}-${name}.cjs`);
  writeFileSync(file, PRELUDE(addonPath) + body);
  const res = spawnSync(runtime.cmd, runtime.args(file), {
    encoding: 'utf8',
    timeout: 120_000,
    env: { ...process.env, NO_COLOR: '1' },
  });
  return {
    ok: res.status === 0 && !res.error,
    status: res.status,
    signal: res.signal,
    stdout: (res.stdout || '').trim(),
    stderr: (res.stderr || '').trim(),
    spawnError: res.error ? String(res.error.message) : null,
  };
}

// Heap errors and aborts that a zero exit code can hide. Deno's double free
// prints after the last user line and has exited 0 in observed runs, so the
// exit code alone is not enough.
const HEAP_ERROR = /double free|corruption|ASSERTION FAILED|Segmentation fault|AddressSanitizer|malloc|panic|Aborted/i;

function available(runtime) {
  const res = spawnSync(runtime.cmd, ['--version'], { encoding: 'utf8', timeout: 30_000 });
  return !res.error && res.status === 0 ? (res.stdout || '').trim().split('\n')[0] : null;
}

function main() {
  const argv = process.argv.slice(2);
  const json = argv.includes('--json');
  const requireAll = argv.includes('--require-all');
  const addonIdx = argv.indexOf('--addon');
  const addonPath = resolve(
    addonIdx !== -1 ? argv[addonIdx + 1] : join(ROOT, 'build', 'index.node')
  );

  if (!existsSync(addonPath)) {
    console.error(`check-runtimes: addon not found: ${addonPath}`);
    console.error('Build it first (pixi run bash build.sh) or pass --addon <path>.');
    process.exit(1);
  }

  const versions = {};
  const present = [];
  for (const rt of RUNTIMES) {
    const v = available(rt);
    if (v) { versions[rt.name] = v; present.push(rt); }
    else if (rt.control) {
      console.error('check-runtimes: node is the control and must be present');
      process.exit(1);
    } else if (requireAll) {
      console.error(`check-runtimes: ${rt.name} is not installed and --require-all was passed`);
      process.exit(1);
    }
  }

  const dir = mkdtempSync(join(tmpdir(), 'napi-mojo-runtimes-'));
  const failures = [];
  const rows = [];

  try {
    // --- 1. surface ------------------------------------------------------
    for (const [name, body] of SCENARIOS) {
      const control = runScenario(RUNTIMES[0], addonPath, body, dir, name);
      if (!control.ok || HEAP_ERROR.test(control.stderr)) {
        failures.push(`node/${name}: the control itself failed — ${control.stderr || control.spawnError || `exit ${control.status}`}`);
        continue;
      }
      for (const rt of present.slice(1)) {
        const got = runScenario(rt, addonPath, body, dir, name);
        let verdict = 'ok';
        if (!got.ok) {
          verdict = `exit ${got.status}${got.signal ? ` (${got.signal})` : ''}`;
        } else if (HEAP_ERROR.test(got.stderr)) {
          verdict = `heap error: ${got.stderr.split('\n')[0]}`;
        } else if (got.stdout !== control.stdout) {
          verdict = 'output differs from node';
        }
        rows.push({ kind: 'surface', runtime: rt.name, scenario: name, verdict });
        if (verdict !== 'ok') {
          failures.push(
            `${rt.name}/${name}: ${verdict}\n` +
            (got.stdout !== control.stdout
              ? `    node: ${control.stdout.replace(/\n/g, ' | ')}\n    ${rt.name}: ${got.stdout.replace(/\n/g, ' | ')}\n`
              : '') +
            (got.stderr ? `    stderr: ${got.stderr.split('\n').slice(0, 3).join(' / ')}` : '')
          );
        }
      }
    }

    // --- 2. known defects ------------------------------------------------
    for (const defect of KNOWN_DEFECTS) {
      const rt = present.find((r) => r.name === defect.runtime);
      if (!rt) {
        rows.push({ kind: 'defect', runtime: defect.runtime, scenario: defect.id, verdict: 'skipped (runtime absent)' });
        continue;
      }
      const got = runScenario(rt, addonPath, defect.body, dir, defect.id);
      const reproduced = defect.expect.test(got.stderr) || defect.expect.test(got.stdout) || !got.ok;
      rows.push({
        kind: 'defect',
        runtime: defect.runtime,
        scenario: defect.id,
        verdict: reproduced ? 'still reproduces' : 'NO LONGER REPRODUCES',
      });
      if (!reproduced) {
        failures.push(
          `${defect.runtime}/${defect.id}: no longer reproduces — ${versions[rt.name]} appears to have fixed it.\n` +
          `    Remove the entry from KNOWN_DEFECTS in scripts/check-runtimes.mjs, and revisit anything\n` +
          `    the framework shaped around it. (${defect.note})`
        );
      }
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }

  if (json) {
    console.log(JSON.stringify({ addon: addonPath, versions, rows, failures }, null, 2));
    process.exit(failures.length ? 1 : 0);
  }

  console.log('check-runtimes: ' + Object.entries(versions).map(([k, v]) => `${k} (${v})`).join(', '));
  console.log(`addon: ${addonPath}\n`);
  for (const r of rows) {
    const mark = r.verdict === 'ok' || r.verdict === 'still reproduces' ? '  ok  ' : 'FAIL  ';
    console.log(`${mark}${r.kind === 'defect' ? 'defect ' : ''}${r.runtime.padEnd(5)} ${r.scenario.padEnd(32)} ${r.verdict}`);
  }
  const absent = RUNTIMES.filter((r) => !versions[r.name]).map((r) => r.name);
  if (absent.length) console.log(`\nnot installed, not checked: ${absent.join(', ')}`);

  if (failures.length) {
    console.error(`\ncheck-runtimes: ${failures.length} failure(s)\n`);
    for (const f of failures) console.error('  ' + f + '\n');
    process.exit(1);
  }
  console.log(`\ncheck-runtimes: ${rows.length} check(s) passed`);
}

main();
