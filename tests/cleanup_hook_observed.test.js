'use strict';
// Observes that a sync env cleanup hook actually RUNS at teardown.
//
// cleanup_hook.test.js asserts registration returns true — which would all
// still pass if hooks silently never fired (the finalizer_gc.test.js trap).
// Hooks fire at env teardown, which never happens inside a live Jest worker,
// so the observation needs a CHILD process: the addon's observable hook
// prints a marker from the no-env hook context (plain stdio — the one
// observable channel legal there), and the parent asserts it appeared after
// the program's own output.
const { execFileSync, spawnSync } = require('child_process');
const path = require('path');

const ADDON = path.join(__dirname, '..', 'build', 'index.node');
const MARKER = 'napi-mojo-cleanup-hook-ran';

test('sync env cleanup hook runs at env teardown (child process)', () => {
  const out = execFileSync(
    process.execPath,
    [
      '-e',
      `const m = require(${JSON.stringify(ADDON)});
       if (m.addObservableCleanupHook() !== true) process.exit(2);
       console.log('registered');`,
    ],
    { encoding: 'utf8', timeout: 30000 }
  );
  expect(out).toContain('registered');
  expect(out).toContain(MARKER);
  // Teardown ordering: the marker must come after normal program output.
  expect(out.indexOf(MARKER)).toBeGreaterThan(out.indexOf('registered'));
});

// Each call is a hook of its own. Both calls used to register the same
// (hook, NULL) pair, and Node refuses a duplicate pair with a CHECK that
// aborts the process; Deno panics the same way.
test('two registrations in one env are two hooks, and both run at teardown', () => {
  const res = spawnSync(
    process.execPath,
    [
      '-e',
      `const m = require(${JSON.stringify(ADDON)});
       m.addObservableCleanupHook();
       m.addObservableCleanupHook();
       console.log('registered twice');`,
    ],
    { encoding: 'utf8', timeout: 30000 }
  );
  expect({ status: res.status, signal: res.signal, stderr: res.stderr }).toEqual({
    status: 0,
    signal: null,
    stderr: '',
  });
  expect(res.stdout.trim().split('\n')).toEqual(['registered twice', MARKER, MARKER]);
});

test('hook does not fire when never registered', () => {
  const out = execFileSync(
    process.execPath,
    ['-e', `require(${JSON.stringify(ADDON)}); console.log('loaded');`],
    { encoding: 'utf8', timeout: 30000 }
  );
  expect(out).toContain('loaded');
  expect(out).not.toContain(MARKER);
});
