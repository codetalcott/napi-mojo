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
// Update node_modules entries for optional platform packages
for (const dep of Object.keys(rootPkg.optionalDependencies || {})) {
  const key = `node_modules/${dep}`;
  if (lock.packages?.[key]) {
    lock.packages[key].version = version;
  }
}
writeFileSync(lockPath, JSON.stringify(lock, null, 2) + '\n');
console.log(`package-lock.json → ${version}`);

console.log(`\nAll packages synced to v${version}`);
