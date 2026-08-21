#!/usr/bin/env node
// Counterfactual gate for src/napi/keepalive.mojo.
//
// pin_across_ffi() exists because the move-discard (`_ = x^`) that
// docs/plan-origin-migration.md prescribes is a no-op for trivially
// register-passable types — which is nearly every FFI slot in this framework.
// A keep-alive that does nothing is worse than none: it reads as done.
//
// This compiles spike/keepalive_probe.mojo to LLVM IR and asserts BOTH halves:
//
//   with_pin     keeps its alloca and carries the escape-plus-clobber barrier
//   without_pin  loses its alloca entirely
//
// The second assertion is the load-bearing one. Without it the gate would pass
// on a compiler where BOTH forms happen to work, and would stop being evidence
// that the barrier does anything.
//
// A failure here is a FINDING — compiler behaviour changed in the exact area
// this framework's FFI safety depends on — not gate noise. Same standing as
// the docstring gate's KNOWN_UNDOCUMENTABLE list.
//
// The Mojo driver defaults to `pixi run mojo`. Override with $NAPI_MOJO_MOJO.

import { execFileSync } from 'node:child_process';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const PROBE = 'spike/keepalive_probe.mojo';
const driver = (process.env.NAPI_MOJO_MOJO ?? 'pixi run mojo').split(/\s+/);
const out = join(mkdtempSync(join(tmpdir(), 'napi-mojo-keepalive-')), 'probe.ll');

execFileSync(driver[0], [...driver.slice(1), 'build', '--emit', 'llvm', '-I', 'src', PROBE, '-o', out], {
  stdio: ['ignore', 'inherit', 'inherit'],
});

const ir = readFileSync(out, 'utf8');
function body(name) {
  const m = ir.match(new RegExp(`define[^\\n]*@${name}\\(([^]*?)\\n\\}`));
  if (!m) throw new Error(`${PROBE}: no @${name} in the emitted IR — did the export name change?`);
  return m[0];
}

const pinned = body('keepalive_probe_with_pin');
const unpinned = body('keepalive_probe_without_pin');
const failures = [];

if (!/\balloca\b/.test(pinned)) {
  failures.push('with_pin lost its alloca — pin_across_ffi no longer pins the slot.');
}
if (!/asm sideeffect[^\n]*~\{memory\}/.test(pinned)) {
  failures.push(
    'with_pin has no `asm sideeffect ... ~{memory}` barrier — std.benchmark.keep ' +
      'no longer emits the escape-plus-clobber it is relied on for.',
  );
}
if (/\balloca\b/.test(unpinned)) {
  failures.push(
    'without_pin KEPT its alloca. Either the compiler now honours `_ = x^` for ' +
      'trivial register types (good news — retire this gate and simplify ' +
      'keepalive.mojo), or the probe stopped exercising the case.',
  );
}

if (failures.length) {
  console.error(`keepalive barrier gate FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  - ${f}`);
  console.error(`\nIR at ${out}`);
  process.exit(1);
}
console.log(
  'keepalive barrier: with_pin retains its slot behind an `asm sideeffect ~{memory}` ' +
    'barrier; without_pin (`_ = x^`) is optimized away entirely.',
);
