#!/usr/bin/env node
/**
 * Syncs the version from the root package.json to all platform packages
 * and the optionalDependencies in the root package.json.
 *
 * Usage: node scripts/sync-versions.mjs [version]
 *   If version is provided, sets it everywhere.
 *   If omitted, reads from root package.json and propagates.
 *
 *        node scripts/sync-versions.mjs --check
 *   Writes nothing; verifies every manifest already agrees with the root
 *   package.json version. Exit 1 (with a list of the drifted files) if not.
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

const lockPath = join(root, 'package-lock.json');
const pixiPath = join(root, 'pixi.toml');

// Anchored to the [workspace] table's `version` key: `^version =` with the `m`
// flag would also match a `version` key in any later table. Group 1 is the
// prefix (so the write path can substitute), group 2 the current value (so the
// check path can compare) — one definition, so the two modes cannot drift.
const PIXI_VERSION_RE = /(\[workspace\][\s\S]*?^version\s*=\s*)"([^"]*)"/m;

const rootPkgPath = join(root, 'package.json');
const rootPkg = JSON.parse(readFileSync(rootPkgPath, 'utf8'));

// `--check` is a read-only audit of exactly the invariants the write path
// establishes. It exists because grail.yaml's `project.versions.synced` needs
// one: that condition ran `--check 2>/dev/null || true`, which was a no-op that
// could only ever report PASS — and, before the argv validation below landed,
// was the very invocation that stamped the literal string "--check" into every
// manifest as the version. Parsed before the flag guard, since a real flag now
// has to survive it.
const argv = process.argv.slice(2);
const checkIdx = argv.indexOf('--check');
const checkOnly = checkIdx !== -1;
if (checkOnly) argv.splice(checkIdx, 1);

const version = argv[0] || rootPkg.version;

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
    `       The only option is --check.`,
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

if (checkOnly) {
  // Note that the semver guard above has already run against rootPkg.version,
  // so a root package.json holding garbage fails here rather than being taken
  // as the standard everything else is measured against.
  const drift = [];
  const expect = (label, actual) => {
    if (actual !== version) {
      drift.push(`${label}: ${JSON.stringify(actual ?? null)} (expected ${JSON.stringify(version)})`);
    }
  };

  for (const [dep, range] of Object.entries(rootPkg.optionalDependencies ?? {})) {
    expect(`package.json optionalDependencies["${dep}"]`, range);
  }

  for (const rel of platformPkgs) {
    expect(rel, JSON.parse(readFileSync(join(root, rel), 'utf8')).version);
  }

  const lockDoc = JSON.parse(readFileSync(lockPath, 'utf8'));
  expect('package-lock.json version', lockDoc.version);
  if (lockDoc.packages?.['']) {
    expect('package-lock.json packages[""].version', lockDoc.packages[''].version);
    for (const [dep, range] of Object.entries(lockDoc.packages[''].optionalDependencies ?? {})) {
      expect(`package-lock.json packages[""].optionalDependencies["${dep}"]`, range);
    }
  }

  for (const dep of Object.keys(rootPkg.optionalDependencies ?? {})) {
    const key = `node_modules/${dep}`;
    const entry = lockDoc.packages?.[key];
    if (!entry) continue;
    expect(`package-lock.json ${key}.version`, entry.version);
    // A `resolved` URL naming a different version than the entry's `version` is
    // the exact defect the write path deletes these fields to avoid: `npm ci`
    // fetches the URL, not the version, so three suites once ran against a
    // v0.2.10 registry binary while the lockfile read 0.6.0. Absent is fine, and
    // so is a URL that agrees — npm legitimately re-adds both once the version
    // is actually published, and failing on that would make a healthy repo dirty
    // after every `npm install`.
    const resolvedVersion = /-(\d[^/]*)\.tgz$/.exec(entry.resolved ?? '')?.[1];
    if (resolvedVersion !== undefined && resolvedVersion !== version) {
      drift.push(
        `package-lock.json ${key}.resolved points at ${JSON.stringify(resolvedVersion)} ` +
        `(expected ${JSON.stringify(version)}) — \`npm ci\` would install that tarball`,
      );
    }
  }

  const pixiMatch = PIXI_VERSION_RE.exec(readFileSync(pixiPath, 'utf8'));
  if (pixiMatch === null) {
    drift.push('pixi.toml: no `version` key found in the [workspace] table');
  } else {
    expect('pixi.toml [workspace] version', pixiMatch[2]);
  }

  if (drift.length > 0) {
    console.error(`error: ${drift.length} version(s) out of sync with package.json (${version}):`);
    for (const d of drift) console.error(`  - ${d}`);
    console.error('\nRun `node scripts/sync-versions.mjs` to fix. Nothing was written.');
    process.exit(1);
  }

  console.log(`All packages in sync at v${version}`);
  process.exit(0);
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
const pixi = readFileSync(pixiPath, 'utf8');
// Test for the match separately from comparing the result: on a re-run the
// replacement is identical to the input, so `next === pixi` means "already
// correct", not "pattern missing". Conflating the two makes a no-op re-run
// print a warning that is simply false.
if (!PIXI_VERSION_RE.test(pixi)) {
  console.error(
    `WARNING: pixi.toml [workspace] version not updated — pattern did not match.`,
  );
} else {
  writeFileSync(pixiPath, pixi.replace(PIXI_VERSION_RE, `$1"${version}"`));
  console.log(`pixi.toml → ${version}`);
}

console.log(`\nAll packages synced to v${version}`);
