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
    for (const f of ['exports.toml', 'fns.mojo', 'lib.mojo', '.gitignore', 'README.md']) {
      expect(existsSync(path.join(proj, f))).toBe(true);
    }
    expect(readFileSync(path.join(proj, 'lib.mojo'), 'utf8')).toContain(
      'napi_register_module_v1'
    );
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
