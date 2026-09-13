'use strict';
// CLI surface tests — everything that runs WITHOUT a Mojo toolchain:
// scaffold, codegen wrapping, and .d.ts emission. The compile half of the CLI
// (`napi-mojo build`) is exercised end-to-end by the "CLI end-to-end" CI step,
// which has the toolchain.
const { spawnSync } = require('child_process');
const { mkdtempSync, existsSync, readFileSync, rmSync } = require('fs');
const os = require('os');
const path = require('path');

const CLI = path.join(__dirname, '..', 'bin', 'napi-mojo.mjs');

function run(args, opts = {}) {
  return spawnSync(process.execPath, [CLI, ...args], {
    encoding: 'utf8',
    ...opts,
  });
}

let dir;
beforeEach(() => {
  dir = mkdtempSync(path.join(os.tmpdir(), 'napi-mojo-cli-'));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('napi-mojo CLI', () => {
  test('--version prints the package version', () => {
    const pkg = require('../package.json');
    const res = run(['--version']);
    expect(res.status).toBe(0);
    expect(res.stdout.trim()).toBe(pkg.version);
  });

  test('--help lists the commands', () => {
    const res = run(['--help']);
    expect(res.status).toBe(0);
    for (const cmd of ['init', 'generate', 'build']) {
      expect(res.stdout).toContain(cmd);
    }
  });

  test('unknown command exits non-zero with a pointer to --help', () => {
    const res = run(['frobnicate']);
    expect(res.status).not.toBe(0);
    expect(res.stderr).toContain('--help');
  });

  test('init scaffolds a complete addon', () => {
    const proj = path.join(dir, 'proj');
    const res = run(['init', proj]);
    expect(res.status).toBe(0);
    for (const f of ['exports.toml', 'fns.mojo', 'lib.mojo', '.gitignore', 'README.md', 'pixi.toml']) {
      expect(existsSync(path.join(proj, f))).toBe(true);
    }
    expect(readFileSync(path.join(proj, 'lib.mojo'), 'utf8')).toContain(
      'napi_register_module_v1'
    );
  });

  test('scaffolded pixi.toml pins the same max as the framework', () => {
    const proj = path.join(dir, 'pinproj');
    expect(run(['init', proj]).status).toBe(0);
    const pinOf = (t) => /^\s*max\s*=\s*"([^"]+)"/m.exec(t)?.[1];
    const framework = pinOf(
      readFileSync(path.join(__dirname, '..', 'pixi.toml'), 'utf8')
    );
    expect(framework).toBeTruthy();
    expect(pinOf(readFileSync(path.join(proj, 'pixi.toml'), 'utf8'))).toBe(framework);
  });

  test('init refuses a non-empty directory without --force', () => {
    const proj = path.join(dir, 'proj');
    expect(run(['init', proj]).status).toBe(0);
    const second = run(['init', proj]);
    expect(second.status).not.toBe(0);
    expect(second.stderr).toContain('--force');
    expect(run(['init', proj, '--force']).status).toBe(0);
  });

  test('generate produces callbacks, structs, package init, and .d.ts', () => {
    const proj = path.join(dir, 'proj');
    expect(run(['init', proj]).status).toBe(0);
    const res = run(
      ['generate', '--toml', 'exports.toml', '--out', 'generated', '--dts', 'index.d.ts'],
      { cwd: proj }
    );
    expect(res.status).toBe(0);
    for (const f of ['generated/callbacks.mojo', 'generated/structs.mojo', 'generated/__init__.mojo']) {
      expect(existsSync(path.join(proj, f))).toBe(true);
    }
    const callbacks = readFileSync(path.join(proj, 'generated', 'callbacks.mojo'), 'utf8');
    expect(callbacks).toContain('def greet_fn');
    expect(callbacks).toContain('register_generated');
    const dts = readFileSync(path.join(proj, 'index.d.ts'), 'utf8');
    expect(dts).toContain('export function greet(arg0: string): string;');
    expect(dts).toContain('export function add(arg0: number, arg1: number): number;');
  });

  test('generate fails cleanly when the declaration file is missing', () => {
    const res = run(['generate', '--toml', 'nope.toml'], { cwd: dir });
    expect(res.status).not.toBe(0);
    expect(res.stderr).toContain('not found');
  });

  test('build fails cleanly when the entry is missing', () => {
    const res = run(['build', 'nope.mojo'], { cwd: dir });
    expect(res.status).not.toBe(0);
    expect(res.stderr).toContain('not found');
  });
});

// `release --scaffold` is run inside a project that already exists, so it
// must never cost the author work they had. It used to overwrite index.js and
// release.yml unconditionally, replace optionalDependencies wholesale, and
// narrow a package with no `files` down to index.js — dropping whatever `main`
// pointed at from the published tarball.
describe('napi-mojo release --scaffold on an existing project', () => {
  const { writeFileSync, mkdirSync } = require('fs');
  const PLATFORM_KEYS = ['darwin-arm64', 'linux-arm64', 'linux-x64'];
  const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
  const write = (rel, content) => {
    mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
    writeFileSync(path.join(dir, rel), content);
  };

  test('keeps an existing loader and workflow, and says so', () => {
    write('package.json', JSON.stringify({ name: 'myaddon', version: '1.2.3' }));
    write('index.js', '// mine\n');
    write('.github/workflows/release.yml', '# mine\n');
    const res = run(['release', '--scaffold', dir]);
    expect(res.status).toBe(0);
    expect(readFileSync(path.join(dir, 'index.js'), 'utf8')).toBe('// mine\n');
    expect(readFileSync(path.join(dir, '.github/workflows/release.yml'), 'utf8')).toBe('# mine\n');
    expect(res.stdout).toMatch(/kept.*index\.js/);
    expect(res.stdout).toMatch(/kept.*release\.yml/);
    expect(res.stdout).toContain('--force');
  });

  test('--force overwrites them', () => {
    write('package.json', JSON.stringify({ name: 'myaddon', version: '1.2.3' }));
    write('index.js', '// mine\n');
    expect(run(['release', '--scaffold', '--force', dir]).status).toBe(0);
    expect(readFileSync(path.join(dir, 'index.js'), 'utf8')).toContain('load the prebuilt binary');
  });

  test('merges optionalDependencies instead of replacing them', () => {
    write('package.json', JSON.stringify({
      name: 'myaddon', version: '1.2.3', optionalDependencies: { fsevents: '^2.3.0' },
    }));
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    const pkg = readJson(path.join(dir, 'package.json'));
    expect(pkg.optionalDependencies.fsevents).toBe('^2.3.0');
    for (const k of PLATFORM_KEYS) expect(pkg.optionalDependencies[`myaddon-${k}`]).toBe('1.2.3');
  });

  test('leaves an existing main and an absent files field alone, and warns about main', () => {
    write('package.json', JSON.stringify({ name: 'myaddon', version: '1.2.3', main: 'lib/entry.js' }));
    const res = run(['release', '--scaffold', dir]);
    expect(res.status).toBe(0);
    const pkg = readJson(path.join(dir, 'package.json'));
    expect(pkg.main).toBe('lib/entry.js');
    // No `files` means npm publishes the whole project; adding one would
    // narrow it to index.js and drop lib/entry.js from the tarball.
    expect(pkg.files).toBeUndefined();
    expect(res.stdout).toMatch(/main.*lib\/entry\.js/);
  });

  test('adds index.js to an existing files list', () => {
    write('package.json', JSON.stringify({ name: 'myaddon', version: '1.2.3', files: ['lib/'] }));
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    expect(readJson(path.join(dir, 'package.json')).files).toEqual(['lib/', 'index.js']);
  });

  test('re-running patches platform manifests: version synced, author fields kept', () => {
    write('package.json', JSON.stringify({ name: 'myaddon', version: '1.2.3' }));
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    const manifest = path.join(dir, 'npm', 'linux-x64', 'package.json');
    const edited = { ...readJson(manifest), repository: { type: 'git', url: 'git+https://example.com/x.git' } };
    writeFileSync(manifest, JSON.stringify(edited));

    const pkgPath = path.join(dir, 'package.json');
    writeFileSync(pkgPath, JSON.stringify({ ...readJson(pkgPath), version: '1.3.0' }));
    expect(run(['release', '--scaffold', dir]).status).toBe(0);

    const m = readJson(manifest);
    expect(m.version).toBe('1.3.0');
    expect(m.repository.url).toBe('git+https://example.com/x.git');
    expect(readJson(pkgPath).optionalDependencies['myaddon-linux-x64']).toBe('1.3.0');
  });

  test('a project with no package.json gets the full default shape', () => {
    const res = run(['release', '--scaffold', dir]);
    expect(res.status).toBe(0);
    const pkg = readJson(path.join(dir, 'package.json'));
    expect(pkg.main).toBe('index.js');
    expect(pkg.files).toEqual(['index.js']);
    expect(existsSync(path.join(dir, 'index.js'))).toBe(true);
    expect(existsSync(path.join(dir, '.github/workflows/release.yml'))).toBe(true);
  });
});
