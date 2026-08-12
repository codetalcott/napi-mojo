#!/usr/bin/env node
/**
 * Syncs the version from the root package.json to all platform packages
 * and the optionalDependencies in the root package.json.
 *
 * Usage: node scripts/sync-versions.mjs [version]
 *   If version is provided, sets it everywhere.
 *   If omitted, reads from root package.json and propagates.
 */
import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');

const platformPkgs = [
  'npm/darwin-arm64/package.json',
  'npm/linux-x64/package.json',
];

const rootPkgPath = join(root, 'package.json');
const rootPkg = JSON.parse(readFileSync(rootPkgPath, 'utf8'));

const version = process.argv[2] || rootPkg.version;

// VALIDATE BEFORE WRITING ANYTHING.
//
// argv[2] used to be trusted verbatim, and this script writes it into the root
// package.json, both platform package.jsons, package-lock.json and pixi.toml.
// So a single stray argument silently stamped a garbage "version" across the
// whole release surface — observed for real: every manifest ended up with
// `"version": "--check"`. Nothing downstream noticed, because every consumer
// just reads the string back out.
//
// A flag is called out separately from generic junk: it is the likeliest
// mistake (a mistyped `npm version`-style invocation landing here), and
// "looks like a flag" is a far more useful message than "not valid semver".
if (/^-/.test(version)) {
  console.error(
    `error: refusing to use ${JSON.stringify(version)} as a version — it looks like a flag.\n` +
    `       This script takes a bare version: node scripts/sync-versions.mjs 0.7.0\n` +
    `       It accepts no options.`,
  );
  process.exit(1);
}

// Deliberately strict (semver core + optional prerelease/build). This script
// only ever sets release versions for this package; anything else is a typo,
// and being permissive here is what makes the failure silent and wide.
const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
if (!SEMVER.test(version)) {
  console.error(
    `error: ${JSON.stringify(version)} is not a valid semver version.\n` +
    `       Expected MAJOR.MINOR.PATCH (e.g. 0.7.0), optionally with a\n` +
    `       -prerelease and/or +build suffix. Nothing was written.`,
  );
  process.exit(1);
}

// Update root version + optionalDependencies
rootPkg.version = version;
if (rootPkg.optionalDependencies) {
  for (const dep of Object.keys(rootPkg.optionalDependencies)) {
    rootPkg.optionalDependencies[dep] = version;
  }
}
writeFileSync(rootPkgPath, JSON.stringify(rootPkg, null, 2) + '\n');
console.log(`root package.json → ${version}`);

// Update platform packages
for (const rel of platformPkgs) {
  const pkgPath = join(root, rel);
  const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
  pkg.version = version;
  writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
  console.log(`${rel} → ${version}`);
}

// Update package-lock.json
const lockPath = join(root, 'package-lock.json');
const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
lock.version = version;
if (lock.packages?.['']) {
  lock.packages[''].version = version;
  if (lock.packages[''].optionalDependencies) {
    for (const dep of Object.keys(lock.packages[''].optionalDependencies)) {
      lock.packages[''].optionalDependencies[dep] = version;
    }
  }
}
// Update node_modules entries for optional platform packages.
// Also drop `resolved`/`integrity`: relabeling only `version` leaves the URL
// pinned to the OLD tarball, and `npm ci` happily downloads it — that is how
// three test suites silently ran against a v0.2.10 registry binary while the
// lockfile claimed 0.6.0. Without the pins, npm re-resolves by version at
// install time (and skips the optional dep if that version isn't published yet).
for (const dep of Object.keys(rootPkg.optionalDependencies || {})) {
  const key = `node_modules/${dep}`;
  if (lock.packages?.[key]) {
    lock.packages[key].version = version;
    delete lock.packages[key].resolved;
    delete lock.packages[key].integrity;
  }
}
writeFileSync(lockPath, JSON.stringify(lock, null, 2) + '\n');
console.log(`package-lock.json → ${version}`);

// pixi.toml carries its own workspace version. It is not published, so nothing
// breaks when it drifts — which is exactly why it does: at v0.5.0 it still read
// 0.1.0 while every npm package said 0.5.0. Sync it here so the repo has one
// answer to "what version is this?" rather than two.
//
// Deliberately anchored to the [workspace] table's `version` key: `^version =`
// with the `m` flag would also match a `version` key in any later table.
const pixiPath = join(root, 'pixi.toml');
const pixi = readFileSync(pixiPath, 'utf8');
const pixiVersionRe = /(\[workspace\][\s\S]*?^version\s*=\s*)"[^"]*"/m;
// Test for the match separately from comparing the result: on a re-run the
// replacement is identical to the input, so `next === pixi` means "already
// correct", not "pattern missing". Conflating the two makes a no-op re-run
// print a warning that is simply false.
if (!pixiVersionRe.test(pixi)) {
  console.error(
    `WARNING: pixi.toml [workspace] version not updated — pattern did not match.`,
  );
} else {
  writeFileSync(pixiPath, pixi.replace(pixiVersionRe, `$1"${version}"`));
  console.log(`pixi.toml → ${version}`);
}

console.log(`\nAll packages synced to v${version}`);
