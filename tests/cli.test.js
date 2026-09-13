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
    expect(readJson(path.join(dir, 'package.json')).files).toEqual(['lib/', 'index.js', 'load-error.js']);
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
    expect(pkg.files).toEqual(['index.js', 'load-error.js']);
    expect(existsSync(path.join(dir, 'index.js'))).toBe(true);
    expect(existsSync(path.join(dir, '.github/workflows/release.yml'))).toBe(true);
  });
});

describe('napi-mojo release: what the generated setup needs to actually publish', () => {
  const { writeFileSync, mkdirSync, chmodSync } = require('fs');
  const PLATFORMS_ = [
    { key: 'darwin-arm64', conda: 'osx-arm64' },
    { key: 'linux-arm64', conda: 'linux-aarch64' },
    { key: 'linux-x64', conda: 'linux-64' },
  ];
  const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
  const writePkg = (obj) => writeFileSync(path.join(dir, 'package.json'), JSON.stringify(obj));
  const git = (...args) => spawnSync('git', ['-C', dir, ...args], { encoding: 'utf8' });

  // The step's `run: |` body, dedented, so the shell and node quoting are
  // exercised exactly as Actions would run them.
  const stepScript = (workflow, stepName) => {
    const lines = workflow.split('\n');
    const at = lines.findIndex((l) => l.trim() === `- name: ${stepName}`);
    if (at === -1) throw new Error(`no step ${stepName}`);
    const run = lines.findIndex((l, i) => i > at && l.trim() === 'run: |');
    const indent = lines[run].indexOf('run:') + 2;
    const body = [];
    for (const l of lines.slice(run + 1)) {
      if (l.trim() && l.search(/\S/) < indent) break;
      body.push(l.slice(indent));
    }
    return body.join('\n');
  };

  test('init declares every prebuild platform in pixi.toml', () => {
    const proj = path.join(dir, 'proj');
    expect(run(['init', proj]).status).toBe(0);
    const toml = readFileSync(path.join(proj, 'pixi.toml'), 'utf8');
    for (const p of PLATFORMS_) expect(toml).toContain(`"${p.conda}"`);
  });

  test('scaffold adds missing platforms to an existing pixi.toml', () => {
    writePkg({ name: 'myaddon', version: '1.0.0' });
    writeFileSync(path.join(dir, 'pixi.toml'), '[workspace]\nname = "x"\nplatforms = ["osx-arm64", "linux-64"]\n');
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    const toml = readFileSync(path.join(dir, 'pixi.toml'), 'utf8');
    expect(toml).toContain('platforms = ["osx-arm64", "linux-64", "linux-aarch64"]');
  });

  test('repository comes from the GitHub remote and reaches every platform manifest', () => {
    writePkg({ name: 'myaddon', version: '1.0.0' });
    expect(git('init', '-q').status).toBe(0);
    expect(git('remote', 'add', 'origin', 'git@github.com:someone/myaddon.git').status).toBe(0);
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    const url = 'git+https://github.com/someone/myaddon.git';
    expect(readJson(path.join(dir, 'package.json')).repository.url).toBe(url);
    for (const p of PLATFORMS_) {
      expect(readJson(path.join(dir, 'npm', p.key, 'package.json')).repository.url).toBe(url);
    }
  });

  test('no repository and no remote is a warning, because provenance publishing needs one', () => {
    writePkg({ name: 'myaddon', version: '1.0.0' });
    const res = run(['release', '--scaffold', dir]);
    expect(res.status).toBe(0);
    expect(res.stdout).toMatch(/no "repository"/);
  });

  test('platform packages declare what they contain and carry the texts', () => {
    writePkg({ name: 'myaddon', version: '1.0.0', license: 'Apache-2.0' });
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    for (const p of PLATFORMS_) {
      const m = readJson(path.join(dir, 'npm', p.key, 'package.json'));
      expect(m.license).toBe('Apache-2.0 AND MIT AND Apache-2.0 WITH LLVM-exception');
      expect(m.files).toContain('licenses/');
      for (const f of ['NOTICE.txt', 'LICENSE.napi-mojo.txt', 'LICENSE.mojo-runtime.txt']) {
        const text = readFileSync(path.join(dir, 'npm', p.key, 'licenses', f), 'utf8');
        expect(text.length).toBeGreaterThan(200);
      }
    }
  });

  test('a compound author licence is parenthesised in the expression', () => {
    writePkg({ name: 'myaddon', version: '1.0.0', license: 'MIT OR Apache-2.0' });
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    expect(readJson(path.join(dir, 'npm', 'linux-x64', 'package.json')).license)
      .toBe('(MIT OR Apache-2.0) AND MIT AND Apache-2.0 WITH LLVM-exception');
  });

  test('types point at the generated index.d.ts when the project has exports.toml', () => {
    writePkg({ name: 'myaddon', version: '1.0.0', files: ['index.js'] });
    writeFileSync(path.join(dir, 'exports.toml'), '');
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    const pkg = readJson(path.join(dir, 'package.json'));
    expect(pkg.types).toBe('index.d.ts');
    expect(pkg.files).toContain('index.d.ts');
  });

  test('the version script keeps npm version and the platform manifests in step', () => {
    writePkg({ name: 'myaddon', version: '1.0.0' });
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    expect(readJson(path.join(dir, 'package.json')).scripts.version).toContain('napi-mojo release --sync');

    // What `npm version minor` does before running that script.
    const pkg = readJson(path.join(dir, 'package.json'));
    writePkg({ ...pkg, version: '1.1.0' });
    const res = run(['release', '--sync', dir]);
    expect(res.status).toBe(0);
    const synced = readJson(path.join(dir, 'package.json'));
    for (const p of PLATFORMS_) {
      expect(readJson(path.join(dir, 'npm', p.key, 'package.json')).version).toBe('1.1.0');
      expect(synced.optionalDependencies[`myaddon-${p.key}`]).toBe('1.1.0');
    }
  });

  test('an existing version script is kept, with a warning', () => {
    writePkg({ name: 'myaddon', version: '1.0.0', scripts: { version: 'make changelog' } });
    const res = run(['release', '--scaffold', dir]);
    expect(res.status).toBe(0);
    expect(readJson(path.join(dir, 'package.json')).scripts.version).toBe('make changelog');
    expect(res.stdout).toMatch(/already has a "version" script/);
  });

  test('the workflow refuses to publish when versions disagree, and passes when they agree', () => {
    writePkg({ name: 'myaddon', version: '1.0.0' });
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    const script = stepScript(
      readFileSync(path.join(dir, '.github/workflows/release.yml'), 'utf8'),
      'Versions agree'
    );
    const output = path.join(dir, 'github-output');
    const step = () => spawnSync('bash', ['-euo', 'pipefail', '-c', script], {
      cwd: dir, encoding: 'utf8', env: { ...process.env, GITHUB_OUTPUT: output },
    });

    // Status, not an empty stderr: the Guard Malloc recipe in CLAUDE.md
    // injects a library that prints a banner into every child node process.
    const ok = step();
    expect({ status: ok.status, stderr: ok.stderr }).toMatchObject({ status: 0 });
    expect(readFileSync(output, 'utf8')).toBe('version=1.0.0\n');

    const manifest = path.join(dir, 'npm', 'linux-x64', 'package.json');
    writeFileSync(manifest, JSON.stringify({ ...readJson(manifest), version: '0.9.0' }));
    const bad = step();
    expect(bad.status).not.toBe(0);
    expect(bad.stderr).toContain('npm/linux-x64 is 0.9.0');
  });

  test('the workflow generates bindings before building', () => {
    writePkg({ name: 'myaddon', version: '1.0.0' });
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    const wf = readFileSync(path.join(dir, '.github/workflows/release.yml'), 'utf8');
    const generate = wf.indexOf('napi-mojo generate');
    expect(generate).toBeGreaterThan(-1);
    expect(generate).toBeLessThan(wf.indexOf('napi-mojo build --bundle'));
    // Installs exactly what was published, not whatever @latest resolves to.
    expect(wf).not.toContain('myaddon@latest');
    expect(wf).toContain('needs.publish.outputs.version');
  });

  test('--bootstrap publishes placeholders, never the real version, and skips existing packages', () => {
    writePkg({ name: 'myaddon', version: '1.0.0', license: 'MIT' });
    // A fake npm: `view` reports myaddon-linux-x64 as existing and 404s the
    // rest; `publish` records the manifest it was asked to publish.
    const bin = path.join(dir, 'fakebin');
    mkdirSync(bin);
    const log = path.join(dir, 'npm-log.jsonl');
    writeFileSync(path.join(bin, 'npm'), `#!/usr/bin/env node
const fs = require('fs');
const [cmd, ...rest] = process.argv.slice(2);
if (cmd === 'view') {
  if (rest[0] === 'myaddon-linux-x64') { console.log('myaddon-linux-x64'); process.exit(0); }
  console.error('npm error code E404'); process.exit(1);
}
if (cmd === 'publish') {
  const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  fs.appendFileSync(${JSON.stringify(log)}, JSON.stringify({ args: rest, pkg }) + '\\n');
  process.exit(0);
}
process.exit(2);
`);
    chmodSync(path.join(bin, 'npm'), 0o755);
    const res = run(['release', '--bootstrap', dir], {
      env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}` },
    });
    expect({ status: res.status, stderr: res.stderr }).toMatchObject({ status: 0 });
    const published = readFileSync(log, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
    expect(published.map((p) => p.pkg.name).sort()).toEqual(['myaddon', 'myaddon-darwin-arm64', 'myaddon-linux-arm64']);
    for (const p of published) {
      expect(p.pkg.version).toBe('0.0.0-bootstrap.0');
      expect(p.args).toEqual(expect.arrayContaining(['--tag', 'bootstrap', '--access', 'public']));
    }
    expect(res.stdout).toMatch(/exists\s+myaddon-linux-x64/);
  });
});

describe('the scaffolded loader explains load failures', () => {
  const { writeFileSync, mkdirSync } = require('fs');
  const key = `${process.platform}-${process.arch}`;

  const scaffold = () => {
    writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name: 'myaddon', version: '1.0.0' }));
    expect(run(['release', '--scaffold', dir]).status).toBe(0);
    expect(existsSync(path.join(dir, 'load-error.js'))).toBe(true);
  };
  const requireProject = () => spawnSync(process.execPath, ['-e', `
    try { require(${JSON.stringify(dir)}); console.log('loaded'); }
    catch (e) { console.log(JSON.stringify({ code: e.code, message: e.message, cause: e.cause && e.cause.message })); }
  `], { encoding: 'utf8' });

  test('an installed binary that cannot load gets the fix, under the addon name', () => {
    scaffold();
    // Stands in for the platform package on an image with no libstdc++: it
    // resolves, and loading it throws what the dynamic loader throws.
    const fake = path.join(dir, 'node_modules', `myaddon-${key}`);
    mkdirSync(fake, { recursive: true });
    writeFileSync(path.join(fake, 'package.json'), JSON.stringify({ name: `myaddon-${key}`, main: 'index.js' }));
    writeFileSync(path.join(fake, 'index.js'),
      "throw new Error('libstdc++.so.6: cannot open shared object file: No such file or directory');");
    const out = JSON.parse(requireProject().stdout);
    expect(out.code).toBe('ERR_NATIVE_NO_CXX_RUNTIME');
    expect(out.message).toMatch(/^myaddon: /);
    expect(out.message).toContain('TROUBLESHOOTING.md#missing-cpp-runtime');
    expect(out.cause).toContain('libstdc++.so.6');
  });

  test('no binary installed says so, and is not mistaken for a load failure', () => {
    scaffold();
    const out = JSON.parse(requireProject().stdout);
    expect(out.code).toBeUndefined();
    expect(out.message).toContain(`no prebuilt binary is installed for ${key}`);
  });
});
