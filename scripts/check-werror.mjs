#!/usr/bin/env node
// Counterfactual gate for the warnings-as-errors policy.
//
// Every compile of this repo's own Mojo in test.yml carries --Werror (build.sh
// and tests/codegen/build.sh default to it; the inline builds pass it). The
// policy exists because a deprecation that only warns is invisible until
// someone reads the log — 27 of them sat in the build output through the Mojo
// 1.1.0 bump with every signal green (docs/plan-lazily-checked-artifacts.md).
//
// A flag is itself a lazily checked artifact: nothing in the normal path
// proves it still turns a warning into a failure, and the case that matters is
// a warning inside an IMPORTED package — build.sh compiles src/lib.mojo as the
// main module and the whole framework is reached through -I. So this asserts
// BOTH halves on a scratch package with a currently-deprecated spelling:
//
//   without --Werror   exit 0, and the diagnostic is a `warning:` attributed
//                      to the imported module
//   with    --Werror   non-zero exit, and the SAME diagnostic is an `error:`
//
// The first half is what keeps this evidence: when a future toolchain retires
// DEPRECATED_IDIOM (either accepting it silently or rejecting it outright),
// that half fails and the idiom has to be replaced with one the pin currently
// deprecates — the gate cannot quietly stop proving anything. Same standing
// as scripts/check-keepalive-barrier.mjs.
//
// The Mojo driver defaults to `pixi run mojo`. Override with $NAPI_MOJO_MOJO.

import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const driver = (process.env.NAPI_MOJO_MOJO ?? 'pixi run mojo').split(/\s+/);

// Mojo 1.1.0 renamed `@parameter` to `@__parameter` on closures passed as
// parameters; the old spelling warns. If this stops warning, pick another
// deprecation from the current pin's release notes and record it here.
const DEPRECATED_IDIOM = "'@parameter' is deprecated";

const DEP = `def apply_twice[func: def(Int) capturing[_] -> Int](x: Int) -> Int:
    return func(func(x))


def in_package(x: Int) -> Int:
    var k = 3

    @parameter
    def add_k(v: Int) -> Int:
        return v + k

    return apply_twice[add_k](x)
`;

const MAIN = `from pkg.dep import in_package


@export("werror_probe")
def werror_probe(x: Int) abi("C") -> Int:
    return in_package(x)
`;

const dir = mkdtempSync(join(tmpdir(), 'napi-mojo-werror-'));
mkdirSync(join(dir, 'pkg'));
writeFileSync(join(dir, 'pkg', '__init__.mojo'), '');
writeFileSync(join(dir, 'pkg', 'dep.mojo'), DEP);
writeFileSync(join(dir, 'main.mojo'), MAIN);

function build(extra) {
  const r = spawnSync(
    driver[0],
    [...driver.slice(1), 'build', ...extra, '--emit', 'shared-lib', '-I', dir, join(dir, 'main.mojo'), '-o', join(dir, 'out.so')],
    { encoding: 'utf8' }
  );
  if (r.error) throw r.error;
  return { status: r.status, out: `${r.stdout}${r.stderr}` };
}

const problems = [];
const plain = build([]);
if (plain.status !== 0) {
  problems.push(`without --Werror the probe FAILED to build (exit ${plain.status}). The deprecated idiom is now a hard error on this toolchain; replace DEPRECATED_IDIOM.`);
} else if (!new RegExp(`pkg[/\\\\]dep\\.mojo:\\d+:\\d+: warning: ${DEPRECATED_IDIOM}`).test(plain.out)) {
  problems.push('without --Werror the probe built but did NOT warn from the imported module. The idiom no longer deprecates (or the diagnostic format changed); replace DEPRECATED_IDIOM.');
}

const strict = build(['--Werror']);
if (strict.status === 0) {
  problems.push('with --Werror the probe BUILT. The flag no longer turns an imported-module warning into a failure — every --Werror site in CI is now decorative.');
} else if (!new RegExp(`pkg[/\\\\]dep\\.mojo:\\d+:\\d+: error: ${DEPRECATED_IDIOM}`).test(strict.out)) {
  problems.push(`with --Werror the probe failed, but not with the expected diagnostic as an error:\n${strict.out.trim()}`);
}

if (problems.length > 0) {
  console.error('warnings-as-errors counterfactual FAILED:\n');
  for (const p of problems) console.error(`  - ${p}\n`);
  console.error('--- without --Werror ---\n' + plain.out.trim() + '\n--- with --Werror ---\n' + strict.out.trim());
  process.exit(1);
}

console.log(`warnings-as-errors: "${DEPRECATED_IDIOM}" in an imported module warns without --Werror (exit 0) and fails with it (exit ${strict.status}) — both halves hold.`);
