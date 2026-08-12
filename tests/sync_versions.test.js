/**
 * sync-versions.mjs --check
 *
 * The drift cases run against a throwaway fixture tree, not the repo: the script
 * resolves its root from its own __dirname, so testing a mismatch in place would
 * mean editing the real package.json. Only the "repo is currently in sync" case
 * runs against the real files.
 */
const { execFileSync } = require('child_process');
const { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } = require('fs');
const { join } = require('path');
const { tmpdir } = require('os');

const REPO = join(__dirname, '..');
const SCRIPT = join(REPO, 'scripts', 'sync-versions.mjs');

/** Run the script, returning { status, stdout, stderr } instead of throwing. */
function run(scriptPath, args) {
  try {
    const stdout = execFileSync('node', [scriptPath, ...args], { encoding: 'utf8', stdio: 'pipe' });
    return { status: 0, stdout, stderr: '' };
  } catch (e) {
    return { status: e.status, stdout: e.stdout ?? '', stderr: e.stderr ?? '' };
  }
}

/** A minimal but structurally complete fixture repo; `overrides` introduce drift. */
function fixture(overrides = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'sync-versions-'));
  const v = '1.2.3';
  mkdirSync(join(dir, 'scripts'));
  mkdirSync(join(dir, 'npm', 'darwin-arm64'), { recursive: true });
  mkdirSync(join(dir, 'npm', 'linux-x64'), { recursive: true });
  copyFileSync(SCRIPT, join(dir, 'scripts', 'sync-versions.mjs'));

  const write = (rel, obj) =>
    writeFileSync(join(dir, rel), JSON.stringify(obj, null, 2) + '\n');

  write('package.json', {
    name: 'napi-mojo',
    version: overrides.rootVersion ?? v,
    optionalDependencies: {
      '@napi-mojo/darwin-arm64': overrides.optDep ?? v,
      '@napi-mojo/linux-x64': v,
    },
  });
  write('npm/darwin-arm64/package.json', { version: overrides.darwin ?? v });
  write('npm/linux-x64/package.json', { version: v });
  write('package-lock.json', {
    version: v,
    packages: {
      '': { version: overrides.lockRoot ?? v, optionalDependencies: { '@napi-mojo/darwin-arm64': v, '@napi-mojo/linux-x64': v } },
      'node_modules/@napi-mojo/darwin-arm64': {
        version: v,
        ...(overrides.resolved ? { resolved: overrides.resolved } : {}),
      },
    },
  });
  writeFileSync(
    join(dir, 'pixi.toml'),
    `[workspace]\nname = "napi-mojo"\nversion = "${overrides.pixi ?? v}"\n\n[dependencies]\nmax = "==26.5.0"\n`,
  );

  return { dir, script: join(dir, 'scripts', 'sync-versions.mjs') };
}

describe('sync-versions.mjs --check', () => {
  const dirs = [];
  const build = (overrides) => {
    const f = fixture(overrides);
    dirs.push(f.dir);
    return f.script;
  };
  afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

  test('the repo is currently in sync', () => {
    const r = run(SCRIPT, ['--check']);
    expect(r.stderr).toBe('');
    expect(r.status).toBe(0);
  });

  test('passes on a fully consistent tree without writing', () => {
    const script = build();
    const r = run(script, ['--check']);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('in sync at v1.2.3');
  });

  test.each([
    ['a platform package', { darwin: '1.2.2' }, 'npm/darwin-arm64/package.json'],
    ['an optionalDependencies range', { optDep: '1.0.0' }, 'optionalDependencies'],
    ['package-lock.json', { lockRoot: '0.9.0' }, 'package-lock.json packages'],
    ['pixi.toml', { pixi: '0.1.0' }, 'pixi.toml [workspace] version'],
  ])('fails when %s drifts', (_label, overrides, expected) => {
    const script = build(overrides);
    const r = run(script, ['--check']);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain(expected);
  });

  test('fails on a resolved URL pinned to a different version than the entry', () => {
    // The real defect: `npm ci` fetches the URL, so the entry's `version` field
    // being correct is not enough to know which binary gets installed.
    const script = build({
      resolved: 'https://registry.npmjs.org/@napi-mojo/darwin-arm64/-/darwin-arm64-0.2.10.tgz',
    });
    const r = run(script, ['--check']);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('0.2.10');
  });

  test('accepts a resolved URL that agrees, so npm install does not dirty the repo', () => {
    const script = build({
      resolved: 'https://registry.npmjs.org/@napi-mojo/darwin-arm64/-/darwin-arm64-1.2.3.tgz',
    });
    expect(run(script, ['--check']).status).toBe(0);
  });

  test('rejects a root version that is not semver, rather than measuring against it', () => {
    const script = build({ rootVersion: 'v1.2' });
    const r = run(script, ['--check']);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('not a valid semver');
  });

  test('rejects the residue of the original incident: version === "--check"', () => {
    // This is the state the old grail.yaml condition actually produced. It trips
    // the flag guard before the semver one, which is the more useful message.
    const script = build({ rootVersion: '--check' });
    const r = run(script, ['--check']);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('looks like a flag');
  });

  test('still rejects unknown flags', () => {
    const script = build();
    const r = run(script, ['--force']);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('looks like a flag');
  });
});
