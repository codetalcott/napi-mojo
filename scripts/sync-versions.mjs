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
