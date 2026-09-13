#!/usr/bin/env node
// napi-mojo CLI — scaffold, generate, and build Mojo native addons.
//
//   napi-mojo init <dir>       scaffold a new addon (exports.toml + fns.mojo + lib.mojo)
//   napi-mojo generate         TOML → callbacks.mojo/structs.mojo (+ optional .d.ts)
//   napi-mojo build            compile the addon to a .node (+ optional runtime bundling)
//   napi-mojo run <entry.mojo> build and RUN a Mojo program hosted by Node
//   napi-mojo release --scaffold   write the prebuild/publish setup for an addon
//
// The CLI wraps the same machinery this repo releases itself with:
// scripts/generate-addon.mjs, scripts/toml-dts.js, scripts/bundle-runtime.sh.
// No third-party dependencies — argument parsing is deliberately minimal.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync,
  symlinkSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { PLATFORMS } from '../scripts/platforms.mjs';

const require = createRequire(import.meta.url);
const PKG_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const VERSION = JSON.parse(
  readFileSync(join(PKG_ROOT, 'package.json'), 'utf8')
).version;

function fail(msg) {
  console.error(`napi-mojo: ${msg}`);
  process.exit(1);
}

function parseArgs(argv, flagsWithValue, boolFlags = []) {
  const opts = {};
  const positional = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (flagsWithValue.includes(a)) {
      const v = argv[++i];
      if (v === undefined) fail(`${a} requires a value`);
      opts[a.replace(/^--?/, '')] = v;
    } else if (boolFlags.includes(a)) {
      opts[a.replace(/^--?/, '')] = true;
    } else if (a.startsWith('-')) {
      fail(`unknown option "${a}" (see napi-mojo --help)`);
    } else {
      positional.push(a);
    }
  }
  return { opts, positional };
}

// --- mojo compiler resolution -------------------------------------------------
// Priority: --mojo flag > NAPI_MOJO_MOJO env > `pixi run mojo` when a
// pixi.toml is found from cwd upward AND pixi is actually runnable > bare
// `mojo` on PATH.
//
// The pixi-availability check is load-bearing, not defensive politeness.
// `napi-mojo init` scaffolds a pixi.toml so that `init && build` works with no
// toolchain setup; without this check that file would also hijack the build for
// someone who has `mojo` on PATH and no pixi at all, turning a working setup
// into "could not run pixi". Finding a manifest proves a pixi project, not a
// pixi installation.
let _pixiOk;
function pixiAvailable() {
  if (_pixiOk === undefined) {
    const probe = spawnSync('pixi', ['--version'], { stdio: 'ignore' });
    _pixiOk = !probe.error && probe.status === 0;
  }
  return _pixiOk;
}

function resolveMojoCmd(flagValue) {
  const cmd = flagValue || process.env.NAPI_MOJO_MOJO;
  if (cmd) return cmd.split(/\s+/);
  let dir = process.cwd();
  for (;;) {
    if (existsSync(join(dir, 'pixi.toml'))) {
      if (pixiAvailable()) return ['pixi', 'run', 'mojo'];
      break;
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return ['mojo'];
}

// One message for both call sites (build and run), so the advice cannot drift
// between them.
function mojoRunFailure(mojo, err) {
  const lines = [
    `could not run "${mojo[0]}" (${err.message})`,
  ];
  if (mojo[0] === 'pixi') {
    lines.push('  This project has a pixi.toml but pixi is not installed.');
    lines.push('  Install it from https://pixi.sh, or pass --mojo "<command>".');
  } else {
    lines.push('  No Mojo toolchain found. Either:');
    lines.push('    - install pixi (https://pixi.sh) and run from a directory');
    lines.push('      with a pixi.toml (napi-mojo init scaffolds one), or');
    lines.push('    - install Mojo on your PATH (https://mojolang.org/install/), or');
    lines.push('    - pass --mojo "<command>" / set NAPI_MOJO_MOJO.');
  }
  return lines.join('\n');
}

// --- init ---------------------------------------------------------------------

const TEMPLATE_EXPORTS_TOML = `# exports.toml — declare your addon's functions, classes, and structs.
#
# The generator (napi-mojo generate) reads this file and produces
# generated/callbacks.mojo (N-API trampolines with type checking and error
# handling) and generated/structs.mojo. Pure Mojo logic lives in fns.mojo.
# See the napi-mojo README for the full declaration reference.

extra_imports = ["from fns import greet_pure, add_pure"]

[functions.greet]
js_name = "greet"
args = ["string"]
returns = "string"
mojo_fn = "greet_pure"

[functions.add]
js_name = "add"
args = ["number", "number"]
returns = "number"
mojo_fn = "add_pure"
`;

const TEMPLATE_FNS_MOJO = `## fns.mojo — pure Mojo functions (no N-API dependencies).
##
## Each function is referenced by name in exports.toml via \`mojo_fn\`; the
## generator wraps it with a type-checked N-API callback.


def greet_pure(name: String) -> String:
    return "Hello, " + name + "!"


def add_pure(a: Float64, b: Float64) -> Float64:
    return a + b
`;

const TEMPLATE_LIB_MOJO = `## lib.mojo — module entry point.
##
## The only file that touches N-API directly: allocate NapiBindings once,
## register the generated callbacks, done. fns.mojo stays pure Mojo.

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import NapiBindings, init_bindings
from napi.error import throw_js_error
from napi.framework.register import ModuleBuilder
from generated.callbacks import register_generated


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        # Leave a pending JS error so require() throws with a real message
        # instead of silently returning an empty exports object.
        throw_js_error(
            env,
            "addon: failed to resolve N-API symbols (Node.js >= 22.12 required)",
        )
        return exports
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        register_generated(m)
        m.flush()
    except:
        # Throw here too. Returning silently would hand JS a half-populated
        # exports object, and the first missing function would surface as
        # "m.greet is not a function" with nothing pointing at the real cause.
        throw_js_error(env, "addon: failed to register exports")
    return exports
`;

// The scaffolded pixi.toml pins the SAME max version this framework is built
// and tested against, read out of the framework's own pixi.toml rather than
// duplicated here — a second copy of the pin is a thing that drifts, and a
// scaffold pinning a max the framework was never compiled against is worse
// than no pin at all. pixi.toml is in package.json "files" so this resolves
// from an npm install too; if it somehow cannot be read we skip the file and
// say so, rather than guessing a version.
function frameworkMaxPin() {
  try {
    const toml = readFileSync(join(PKG_ROOT, 'pixi.toml'), 'utf8');
    return /^\s*max\s*=\s*"([^"]+)"/m.exec(toml)?.[1] ?? null;
  } catch {
    return null;
  }
}

const TEMPLATE_PIXI_TOML = (name, pin) => `# Provisions the Mojo toolchain for this project.
#
# \`napi-mojo build\` (and \`run\`) use \`pixi run mojo\` when a pixi.toml is in
# scope and pixi is installed, so with this file present you need no other
# toolchain setup — the first build downloads the compiler, later ones reuse it.
# If you would rather use a \`mojo\` already on your PATH, delete this file.
#
# The max version is pinned to the one napi-mojo is built and tested against.
# \`platforms\` lists every prebuild target: the release workflow from
# \`napi-mojo release --scaffold\` builds on each, and pixi refuses to install
# on a platform the workspace does not declare.

[workspace]
name = "${name}"
channels = ["conda-forge", "https://conda.modular.com/max/"]
platforms = [${PLATFORMS.map((p) => `"${p.condaSubdir}"`).join(', ')}]
version = "0.1.0"

[dependencies]
max = "${pin}"
`;

const TEMPLATE_GITIGNORE = `generated/
build/
*.node
.pixi/
`;

const TEMPLATE_README = `# My napi-mojo addon

\`\`\`bash
napi-mojo generate --dts index.d.ts   # exports.toml -> generated/ + index.d.ts
napi-mojo build                       # lib.mojo -> build/index.node
node -e "console.log(require('./build/index.node').greet('world'))"
\`\`\`

Declare functions in \`exports.toml\`, implement them in \`fns.mojo\`, rerun
\`napi-mojo generate\`.

## Toolchain

The included \`pixi.toml\` pins the Mojo version napi-mojo is tested against, so
\`napi-mojo build\` works with no further setup as long as
[pixi](https://pixi.sh) is installed — the first build downloads the compiler
(a few minutes), later ones reuse it.

Prefer a \`mojo\` already on your PATH? Delete \`pixi.toml\`. Need a different
compiler entirely? Pass \`--mojo "<command>"\` or set \`NAPI_MOJO_MOJO\`.
`;

function cmdInit(argv) {
  const { opts, positional } = parseArgs(argv, [], ['--force', '--host']);
  const target = positional[0];
  if (!target) fail('usage: napi-mojo init <dir> [--force] [--host]');
  const dir = resolve(target);
  if (existsSync(dir) && readdirSync(dir).length > 0 && !opts.force) {
    fail(`${dir} exists and is not empty (pass --force to scaffold anyway)`);
  }
  mkdirSync(dir, { recursive: true });

  // --host scaffolds the inverted shape: a Mojo PROGRAM that Node hosts,
  // rather than an addon that JS calls into.
  if (opts.host) {
    const hostFiles = {
      'main.mojo': TEMPLATE_MAIN_MOJO,
      '.gitignore': '.napi-mojo/\n_napi_mojo_host_entry.mojo\n.pixi/\n',
    };
    const hostPin = frameworkMaxPin();
    if (hostPin) {
      hostFiles['pixi.toml'] = TEMPLATE_PIXI_TOML(basename(dir), hostPin);
    }
    for (const [name, content] of Object.entries(hostFiles)) {
      writeFileSync(join(dir, name), content);
      console.log(`  created ${join(target, name)}`);
    }
    console.log(`\nNext steps:
  cd ${target}
  napi-mojo run main.mojo`);
    return;
  }

  const pin = frameworkMaxPin();
  const files = {
    'exports.toml': TEMPLATE_EXPORTS_TOML,
    'fns.mojo': TEMPLATE_FNS_MOJO,
    'lib.mojo': TEMPLATE_LIB_MOJO,
    '.gitignore': TEMPLATE_GITIGNORE,
    'README.md': TEMPLATE_README,
  };
  if (pin) files['pixi.toml'] = TEMPLATE_PIXI_TOML(basename(dir), pin);
  for (const [name, content] of Object.entries(files)) {
    writeFileSync(join(dir, name), content);
    console.log(`  created ${join(target, name)}`);
  }
  if (!pin) {
    console.log(
      '\n  note: could not read napi-mojo\'s pixi.toml, so no pixi.toml was\n' +
      '        scaffolded. Install Mojo yourself, or pass --mojo "<command>".',
    );
  }
  console.log(`\nNext steps:
  cd ${target}
  napi-mojo generate --dts index.d.ts
  napi-mojo build
  node -e "console.log(require('./build/index.node').greet('world'))"`);
}

// --- generate -----------------------------------------------------------------

function cmdGenerate(argv) {
  const { opts, positional } = parseArgs(argv, ['--toml', '--out', '--dts']);
  if (positional.length > 0) fail(`unexpected argument "${positional[0]}"`);
  const tomlPath = resolve(opts.toml || 'exports.toml');
  const outDir = resolve(opts.out || 'generated');
  if (!existsSync(tomlPath)) fail(`declaration file not found: ${tomlPath}`);
  mkdirSync(outDir, { recursive: true });
  // The generated dir is a Mojo package for `from generated.callbacks import …`
  const initPath = join(outDir, '__init__.mojo');
  if (!existsSync(initPath)) writeFileSync(initPath, '');

  const res = spawnSync(
    process.execPath,
    [join(PKG_ROOT, 'scripts', 'generate-addon.mjs')],
    {
      stdio: 'inherit',
      env: { ...process.env, NAPI_MOJO_TOML: tomlPath, NAPI_MOJO_OUT: outDir },
    }
  );
  if (res.status !== 0) process.exit(res.status ?? 1);

  if (opts.dts) {
    const { parseTOML } = require(join(PKG_ROOT, 'scripts', 'toml-lite.js'));
    const { emitTomlDts } = require(join(PKG_ROOT, 'scripts', 'toml-dts.js'));
    const decl = parseTOML(readFileSync(tomlPath, 'utf8'));
    const lines = [
      '// AUTO-GENERATED by napi-mojo generate --dts. Do not edit manually.',
      '',
      ...emitTomlDts(decl),
    ];
    const dtsPath = resolve(opts.dts);
    writeFileSync(dtsPath, lines.join('\n') + '\n');
    console.log(`Generated ${dtsPath}`);
  }
}

// --- build --------------------------------------------------------------------

function cmdBuild(argv) {
  const { opts, positional } = parseArgs(
    argv,
    ['-o', '--out', '--include', '--mojo'],
    ['--bundle']
  );
  const entry = resolve(positional[0] || 'lib.mojo');
  if (!existsSync(entry)) fail(`entry not found: ${entry}`);
  const out = resolve(opts.o || opts.out || join('build', 'index.node'));
  const include = resolve(opts.include || join(PKG_ROOT, 'src'));
  if (!existsSync(join(include, 'napi'))) {
    fail(`include path ${include} does not contain the napi package`);
  }
  mkdirSync(dirname(out), { recursive: true });

  const mojo = resolveMojoCmd(opts.mojo);
  const args = [
    ...mojo.slice(1),
    'build', '--emit', 'shared-lib', '-I', include, entry, '-o', out,
  ];
  console.log(`$ ${mojo[0]} ${args.join(' ')}`);
  const res = spawnSync(mojo[0], args, { stdio: 'inherit' });
  if (res.error) fail(mojoRunFailure(mojo, res.error));
  if (res.status !== 0) process.exit(res.status ?? 1);
  console.log(`Built ${out}`);

  if (opts.bundle) {
    const script = join(PKG_ROOT, 'scripts', 'bundle-runtime.sh');
    const bres = spawnSync('bash', [script, out], { stdio: 'inherit' });
    if (bres.status !== 0) process.exit(bres.status ?? 1);
  }
}

// --- run (host mode) ----------------------------------------------------------
//
// Inverts the usual direction: instead of JS calling into a Mojo addon, a Mojo
// program drives Node and uses npm as its standard library. The user writes
// only mojo_main; everything below is generated per run.
//
// `require` is module-scoped and NOT reachable from Mojo via napi_get_global
// (process.mainModule.require is undefined under ESM and `node -e`), so the
// bootstrap builds one with createRequire and hands it in on the ctx object.

const TEMPLATE_MAIN_MOJO = `## main.mojo — a Mojo program hosted by Node.
##
## Run it with:  napi-mojo run main.mojo
##
## There is no N-API registration boilerplate here: \`napi-mojo run\` generates
## a wrapper that registers mojo_main and launches Node on a bootstrap that
## calls it. \`ctx\` carries { require, argv, cwd } from that bootstrap.

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.framework.js_host import NodeHost
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber


def mojo_main(b: Bindings, env: NapiEnv, ctx: NapiValue) raises -> NapiValue:
    var host = NodeHost.from_context(b, env, ctx)

    host.console_log("hello from Mojo, hosted by Node")

    # npm and the Node builtins are the standard library here.
    var os_mod = host.require("os")
    var platform = os_mod.call_method(b, env, "platform", List[NapiValue]())
    host.console_log("platform: " + JsString.from_napi_value(b, env, platform))

    # A number returned from mojo_main becomes the process exit code.
    return JsNumber.create_int(b, env, 0).value
`;

// The generated wrapper. Sits NEXT TO the user's entry file, because Mojo
// resolves a plain-module import relative to the main module's directory —
// that is what makes `from <entry> import mojo_main` work with no extra -I.
//
// It imports an ALIAS, not the entry's own name. An entry file's basename
// becomes a TOP-LEVEL Mojo module name, so a perfectly reasonable filename
// can be shadowed by an installed package: `pipeline.mojo` resolves to MAX's
// `pipeline` package and fails with "does not contain 'mojo_main'". Adding
// -I <entryDir> does not change that, in either position. So the entry is
// exposed under a `_napi_mojo_src_` prefix that nothing else can claim, and
// compiler diagnostics are rewritten below to point back at the real file.
function hostEntrySource(aliasModule) {
  return `## AUTO-GENERATED by \`napi-mojo run\`. Do not edit; it is rewritten
## every run and removed afterwards (pass --keep to inspect it).

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import NapiBindings, init_bindings
from napi.error import throw_js_error
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder

from ${aliasModule} import mojo_main


def _host_main_cb(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ctx = CbArgs.get_one(b, env, info)
        return mojo_main(b, env, ctx)
    except:
        # Only reached when mojo_main raised WITHOUT leaving a pending JS
        # exception. If it left one, napi_throw_error is a no-op and the
        # original error keeps its identity all the way out to the bootstrap.
        throw_js_error(env, "mojo_main raised")
        return NapiValue(unsafe_from_address=Int(0))


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        throw_js_error(
            env,
            "host: failed to resolve N-API symbols (Node.js >= 22.12 required)",
        )
        return exports
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        var cb_ref = _host_main_cb
        m.method("mojo_main", fn_ptr(cb_ref))
        m.flush()
        _ = cb_ref
    except:
        pass
    return exports
`;
}

function hostBootstrapSource(addonPath, entryDir) {
  return `// AUTO-GENERATED by \`napi-mojo run\`. Do not edit.
const { createRequire } = require('node:module');
const addon = require(${JSON.stringify(addonPath)});

// Rooted at the ENTRY's directory, not this bootstrap's, so that require()
// from Mojo resolves the user's node_modules and relative paths.
const hostRequire = createRequire(${JSON.stringify(entryDir + '/')});

const ctx = {
  require: hostRequire,
  argv: process.argv.slice(2),
  cwd: process.cwd(),
};

const rc = addon.mojo_main(ctx);
if (typeof rc === 'number' && Number.isInteger(rc)) process.exitCode = rc;
`;
}

// Every input `run` supports, hashed: the user's tree, the framework tree, the
// include path, the compiler command and the generated wrapper. `run` accepts
// exactly one -I, so that dependency set is COMPLETE — there is no third
// directory a build could pull from, which is what makes skipping the compile
// safe rather than a stale-binary trap. `--rebuild` is the escape hatch.
function mojoFilesUnder(dir) {
  const out = [];
  const walk = (d) => {
    let entries;
    try { entries = readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries.sort((a, b) => (a.name < b.name ? -1 : 1))) {
      if (e.name.startsWith('.') || e.name.startsWith('_napi_mojo_')) continue;
      const full = join(d, e.name);
      if (e.isDirectory()) walk(full);
      else if (e.name.endsWith('.mojo')) out.push(full);
    }
  };
  walk(dir);
  return out;
}

function buildKey({ entryDir, include, mojoCmd, wrapperSrc }) {
  const h = createHash('sha256');
  for (const part of [VERSION, mojoCmd.join(' '), include, wrapperSrc]) {
    h.update(part);
    h.update('\0');
  }
  for (const f of [...mojoFilesUnder(entryDir), ...mojoFilesUnder(include)]) {
    h.update(f);
    h.update('\0');
    h.update(readFileSync(f));
    h.update('\0');
  }
  return h.digest('hex');
}

function cmdRun(argv) {
  // Split user program args at the first `--` before flag parsing, so that
  // `napi-mojo run main.mojo -- --verbose` passes --verbose to the program.
  const sep = argv.indexOf('--');
  const ownArgs = sep === -1 ? argv : argv.slice(0, sep);
  const userArgs = sep === -1 ? [] : argv.slice(sep + 1);

  const { opts, positional } = parseArgs(
    ownArgs,
    ['--include', '--mojo'],
    ['--keep', '--rebuild']
  );
  const entry = resolve(positional[0] || 'main.mojo');
  if (!existsSync(entry)) fail(`entry not found: ${entry}`);
  if (!entry.endsWith('.mojo')) fail(`entry must be a .mojo file: ${entry}`);

  const entryDir = dirname(entry);
  const moduleName = entry.slice(entryDir.length + 1, -'.mojo'.length);
  const include = resolve(opts.include || join(PKG_ROOT, 'src'));
  if (!existsSync(join(include, 'napi'))) {
    fail(`include path ${include} does not contain the napi package`);
  }

  const workDir = join(entryDir, '.napi-mojo');
  const wrapper = join(entryDir, '_napi_mojo_host_entry.mojo');
  const aliasModule = `_napi_mojo_src_${moduleName}`;
  const alias = join(entryDir, `${aliasModule}.mojo`);
  const addon = join(workDir, 'host.node');
  const bootstrap = join(workDir, 'bootstrap.cjs');
  mkdirSync(workDir, { recursive: true });

  const cleanup = () => {
    if (opts.keep) return;
    try { rmSync(wrapper, { force: true }); } catch {}
    try { rmSync(alias, { force: true }); } catch {}
  };

  const mojo = resolveMojoCmd(opts.mojo);
  const wrapperSrc = hostEntrySource(aliasModule);
  const stamp = join(workDir, 'build.key');
  const key = buildKey({ entryDir, include, mojoCmd: mojo, wrapperSrc });
  const cached =
    !opts.rebuild &&
    existsSync(addon) &&
    existsSync(stamp) &&
    readFileSync(stamp, 'utf8').trim() === key;

  if (cached) {
    // Nothing to do: the compile is ~1.8s of a ~2s run, so this is the
    // difference between `run` feeling like a runtime and like a build tool.
    writeFileSync(bootstrap, hostBootstrapSource(addon, entryDir));
  } else try {
    writeFileSync(wrapper, wrapperSrc);
    // Symlink, so diagnostics carry the real line numbers and nothing is
    // duplicated. Copy is the fallback for filesystems without symlinks.
    rmSync(alias, { force: true });
    try {
      symlinkSync(`${moduleName}.mojo`, alias);
    } catch {
      copyFileSync(entry, alias);
    }

    const args = [
      ...mojo.slice(1),
      'build', '--emit', 'shared-lib', '-I', include, wrapper, '-o', addon,
    ];
    // Captured rather than inherited so the alias filename can be rewritten
    // back to the user's own — otherwise every compile error in host mode
    // names a file the user never wrote.
    const bres = spawnSync(mojo[0], args, { encoding: 'utf8' });
    if (bres.error) {
      fail(mojoRunFailure(mojo, bres.error));
    }
    const unalias = (t) =>
      (t || '').split(`${aliasModule}.mojo`).join(`${moduleName}.mojo`);
    if (bres.stdout) process.stdout.write(unalias(bres.stdout));
    if (bres.stderr) process.stderr.write(unalias(bres.stderr));
    if (bres.status !== 0) {
      cleanup();
      process.exit(bres.status ?? 1);
    }

    writeFileSync(stamp, `${key}\n`);
    writeFileSync(bootstrap, hostBootstrapSource(addon, entryDir));
  } finally {
    cleanup();
  }

  const res = spawnSync(process.execPath, [bootstrap, ...userArgs], {
    stdio: 'inherit',
  });
  if (res.error) fail(`could not run node (${res.error.message})`);
  process.exit(res.status ?? 1);
}

// --- entry --------------------------------------------------------------------

// --- release --scaffold -------------------------------------------------------
//
// Everything between "my addon compiles" and "someone can npm install it" —
// the part `napi-mojo build --bundle` stops short of. One bundled binary is
// one platform on one machine; publishing means a prebuild per platform, an
// optionalDependencies fan-out so npm picks the right one, and a workflow
// that proves each tarball works somewhere other than where it was built.
//
// The shapes here are the ones this repo and its sibling m0serve arrived at
// the hard way; the comments in the generated files say which failure each
// one is for, because a scaffold that only works is a scaffold nobody can
// maintain.

const TEMPLATE_LOADER = (name) => `// ${name} — load the prebuilt binary for this platform.
//
// npm installs exactly one of the optionalDependencies below, chosen by the
// "os"/"cpu" fields in each platform package. A local build takes priority so
// that \`napi-mojo build\` and \`npm test\` exercise what you just compiled
// rather than the last published release — a stale registry binary passing
// your tests is a hard failure to spot.
//
// A binary that is installed but cannot LOAD — a container image without the
// C++ runtime, a glibc that is too old, Alpine — is explained by load-error.js,
// which names the fix and links to it. Not having a binary installed at all is
// a different failure, reported separately below; the two must not share a
// catch, or users are told nothing is installed while the binary sits there.
'use strict';

const { existsSync } = require('node:fs');
const { join } = require('node:path');
const { explainLoadError } = require('./load-error.js');

const NAME = ${JSON.stringify(name)};
const local = join(__dirname, 'build', 'index.node');
const key = \`\${process.platform}-\${process.arch}\`;
const platformPackage = \`\${NAME}-\${key}\`;

function load(id) {
  try {
    return require(id);
  } catch (err) {
    throw explainLoadError(err, { name: NAME });
  }
}

function installed(id) {
  try {
    require.resolve(id);
    return true;
  } catch {
    return false;
  }
}

if (existsSync(local)) {
  module.exports = load(local);
} else if (installed(platformPackage)) {
  module.exports = load(platformPackage);
} else {
  throw new Error(
    \`\${NAME}: no prebuilt binary is installed for \${key} (\${platformPackage}), and there is no local build at \${local}.\\n\` +
    'Reinstall without --no-optional / --omit=optional, or build from source with \`npx napi-mojo build\`.'
  );
}
`;

// Takes the manifest already on disk (or {}) and patches it: the fields that
// must agree with the root package and the platform are reset, everything
// else the author added — repository, license, keywords — is kept. That is
// what makes re-running the scaffold a safe way to resync versions.
//
// `license` and `repository` are owned too, derived from the root package:
// the licence has to describe what the tarball CONTAINS (see platformLicense),
// and `npm publish --provenance` rejects a package whose repository.url does
// not match the repository the workflow runs in — so a platform manifest
// without one fails every CI publish.
const TEMPLATE_PLATFORM_PKG = (p, name, version, existing = {}, { license, repository } = {}) => {
  const owned = {
    name: `${name}-${p.key}`,
    version,
    main: 'index.node',
    // The trailing `*` is load-bearing on Linux: sonames are versioned and a
    // bare "*.so" silently drops them from the tarball. That shipped from
    // napi-mojo itself, twice.
    files: [...new Set(['index.node', p.libGlob, 'licenses/', ...(existing.files || [])])],
    os: [p.os],
    cpu: [p.cpu],
    license,
    ...(repository ? { repository } : {}),
  };
  // Listing `owned` first fixes the key order of a new manifest; `existing`
  // then supplies the author's values, and `owned` again wins where it must.
  return JSON.stringify({
    ...owned,
    description: `${name} prebuilt binary for ${p.key}`,
    ...existing,
    ...owned,
  }, null, 2) + '\n';
};

// A prebuilt package is not the author's source alone: index.node has the
// napi-mojo framework compiled into it (MIT), and the Mojo runtime libraries
// bundled beside it are Modular's (the non-MIT terms of `p.license` in
// scripts/platforms.mjs — the same declaration napi-mojo's own packages use).
// The author's licence joins those terms rather than replacing them.
function platformLicense(p, authorLicense) {
  const terms = p.license.split(' AND ');
  if (!authorLicense || /^(UNLICENSED|SEE LICENSE)/i.test(authorLicense)) return terms.join(' AND ');
  const author = /\s(OR|AND)\s/.test(authorLicense) && !/^\(.*\)$/.test(authorLicense)
    ? `(${authorLicense})`
    : authorLicense;
  return [...new Set([author, ...terms])].join(' AND ');
}

// Copied beside every platform package, so the tarball carries the texts its
// `license` names. LICENSE.* files from platforms.mjs are Modular's runtime
// licence; napi-mojo's own NOTICE.bundle.txt describes napi-mojo's packages,
// so an addon gets this NOTICE instead.
const TEMPLATE_PLATFORM_NOTICE = (name, p, authorLicense) => `${name}-${p.key} — what is inside, and under what terms
${'='.repeat(`${name}-${p.key} — what is inside, and under what terms`.length)}

This package is not source. It ships a compiled index.node together with the
Mojo runtime libraries it needs, so that installing it requires no Mojo
toolchain.

index.node
  Compiled from ${name}'s own source${authorLicense ? ` (${authorLicense})` : ''}, with the napi-mojo framework
  compiled in. napi-mojo is MIT licensed: see LICENSE.napi-mojo.txt.

Mojo runtime libraries (every other shared library in this package)
  From the Modular repository (https://github.com/modular/modular),
  Copyright Modular Inc, under the Apache License 2.0 with LLVM Exceptions.
  Full text: LICENSE.mojo-runtime.txt.

  MODIFICATION NOTICE (Apache License 2.0, section 4(b)): each of these files
  was changed by napi-mojo's scripts/bundle-runtime.sh at build time. Its
  install name and rpath (Mach-O) or RUNPATH (ELF) were rewritten so the set
  resolves beside itself, and on macOS each was re-signed ad-hoc. No source
  was changed and nothing was recompiled.

Generated by \`napi-mojo release --scaffold\`; re-running it refreshes this file.
`;

// "https://github.com/o/r", "git@github.com:o/r.git" → the repository object
// npm provenance compares against the workflow's repository.
function repositoryFromGit(dir) {
  const res = spawnSync('git', ['-C', dir, 'remote', 'get-url', 'origin'], { encoding: 'utf8' });
  if (res.error || res.status !== 0) return null;
  const m = /github\.com[:/]([^/\s]+)\/([^/\s]+?)(?:\.git)?\/?$/.exec(res.stdout.trim());
  return m ? { type: 'git', url: `git+https://github.com/${m[1]}/${m[2]}.git` } : null;
}

// The version every manifest must agree on is the root package's. Patches
// optionalDependencies and each npm/<platform>/package.json to it, touching
// nothing else — so it is safe as an npm `version` lifecycle script.
function syncVersions(dir) {
  const pkgPath = join(dir, 'package.json');
  if (!existsSync(pkgPath)) fail(`${pkgPath} does not exist`);
  const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
  if (!pkg.name || !pkg.version) fail('package.json needs a name and a version');
  const changed = [];
  const writeJson = (abs, obj) => { writeFileSync(abs, JSON.stringify(obj, null, 2) + '\n'); changed.push(abs); };

  const deps = { ...(pkg.optionalDependencies || {}) };
  let depsChanged = false;
  for (const p of PLATFORMS) {
    const dep = `${pkg.name}-${p.key}`;
    if (deps[dep] !== pkg.version) { deps[dep] = pkg.version; depsChanged = true; }
    const manifestPath = join(dir, 'npm', p.key, 'package.json');
    if (!existsSync(manifestPath)) fail(`${manifestPath} does not exist — run \`napi-mojo release --scaffold\` first`);
    const m = JSON.parse(readFileSync(manifestPath, 'utf8'));
    if (m.version !== pkg.version) writeJson(manifestPath, { ...m, version: pkg.version });
  }
  if (depsChanged) writeJson(pkgPath, { ...pkg, optionalDependencies: deps });
  return { name: pkg.name, version: pkg.version, changed };
}

const TEMPLATE_RELEASE_WORKFLOW = (name) => `# Build a prebuild per platform, prove each one, then publish.
#
# Generated by \`napi-mojo release --scaffold\`. Four things in here are not
# obvious and are worth keeping:
#
#   1. The consume job has NO checkout and NO toolchain. It installs the
#      tarball the way a user would and runs it. If you add \`actions/checkout\`
#      "to get a test app", the job starts proving something else — it was
#      exactly that shape of test, passing on the machine that built the
#      artifact, that let napi-mojo ship a broken linux-x64 package.
#   2. check-portable.mjs reads the binary's load commands. A load test on the
#      build machine cannot tell you whether a recorded rpath points at the
#      runner's own directory, because there it still resolves.
#   3. npm's OIDC trusted publishing cannot BOOTSTRAP a package. Every package
#      this publishes must already exist on the registry with a trusted
#      publisher configured; \`npx napi-mojo release --bootstrap\` publishes
#      placeholders (0.0.0-bootstrap.0, dist-tag "bootstrap") so no real
#      version is burned on a package with no binary. Skipping it fails here
#      as \`E404 ... PUT\`, which for a scoped package is an authorization error.
#   4. Versions must agree across package.json, its optionalDependencies and
#      npm/*/package.json. The publish job checks that before pushing anything;
#      \`npx napi-mojo release --sync\` fixes it (the scaffold wires it to
#      \`npm version\`).
name: Release

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  build:
    strategy:
      # One platform failing must not cancel the others: a release missing a
      # prebuild is recoverable, a release where you cannot see which
      # platforms broke is not.
      fail-fast: false
      matrix:
        include:
${PLATFORMS.map((p) => `          - os: ${p.runner}\n            platform: ${p.key}`).join('\n')}
    runs-on: \${{ matrix.os }}

    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
      - uses: prefix-dev/setup-pixi@v0.10.1
        with:
          pixi-version: latest

      # npm ci, so the release builds what the lockfile pins. It requires a
      # committed package-lock.json; a plain install here would let a
      # transitive bump ride into a release unreviewed.
      - run: npm ci

      # bundle-runtime.sh shells out to patchelf. It is preinstalled on the
      # x64 runner image today, which is an image detail and not a guarantee.
      - name: Ensure patchelf (Linux)
        if: runner.os == 'Linux'
        run: command -v patchelf || (sudo apt-get update && sudo apt-get install -y patchelf)

      # \`build\` compiles lib.mojo, which imports generated/ — and generated/ is
      # gitignored by \`napi-mojo init\`, so a fresh checkout does not have it.
      - name: Generate bindings
        run: |
          if [ -f exports.toml ]; then
            npx napi-mojo generate --dts index.d.ts
          fi

      - name: Build and bundle
        run: npx napi-mojo build --bundle

      - name: Test
        run: npm run test --if-present

      # The property a load attempt on this machine cannot establish. Checked
      # in a directory holding ONLY what ships, not in build/: there, a
      # leftover library the manifest forgot would satisfy the check and then
      # be missing from the published package.
      - name: Verify the bundle does not depend on this machine
        run: |
          set -euo pipefail
          stage="\$RUNNER_TEMP/consumer-layout"
          rm -rf "\$stage" && mkdir -p "\$stage"
          cp build/index.node "\$stage/"
          while read -r lib; do
            [ -n "\$lib" ] || continue
            cp "build/\$lib" "\$stage/\$lib"
          done < build/bundled-libs.txt
          node node_modules/napi-mojo/scripts/check-portable.mjs \\
            --require-self-contained --manifest build/bundled-libs.txt "\$stage/index.node"

      - uses: actions/upload-artifact@v7
        with:
          name: \${{ matrix.platform }}
          path: |
            build/index.node
            build/bundled-libs.txt
            build/*.dylib*
            build/*.so*
          if-no-files-found: error

  publish:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write          # npm OIDC trusted publishing
    outputs:
      version: \${{ steps.version.outputs.version }}
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '24'
          registry-url: 'https://registry.npmjs.org'

      # Before anything is pushed: a platform manifest left at the previous
      # version makes \`npm publish\` fail with E403 halfway through a release,
      # after some packages are already out.
      - name: Versions agree
        id: version
        run: |
          node -e "
            const fs = require('fs');
            const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
            const bad = [];
            for (const key of '${PLATFORMS.map((p) => p.key).join(' ')}'.split(' ')) {
              const dep = pkg.name + '-' + key;
              const m = JSON.parse(fs.readFileSync('npm/' + key + '/package.json', 'utf8'));
              if (m.version !== pkg.version) bad.push('npm/' + key + ' is ' + m.version);
              if ((pkg.optionalDependencies || {})[dep] !== pkg.version) bad.push('optionalDependencies[' + dep + '] is ' + (pkg.optionalDependencies || {})[dep]);
            }
            if (bad.length) {
              console.error('::error::versions disagree with package.json ' + pkg.version + ': ' + bad.join('; ') + '. Run npx napi-mojo release --sync and commit.');
              process.exit(1);
            }
            fs.appendFileSync(process.env.GITHUB_OUTPUT, 'version=' + pkg.version + '\\\\n');
          "

      # npm 11.5.1+ for trusted publishing; Node 24 ships an older npm.
      - run: npm install -g npm@latest

      # The root package's index.d.ts is generated from exports.toml, like the
      # bindings, so it is not in the checkout either.
      - name: Generate type declarations
        run: |
          if [ -f exports.toml ]; then
            npm ci --ignore-scripts
            npx napi-mojo generate --dts index.d.ts
          fi

      - uses: actions/download-artifact@v8
        with:
          path: artifacts

      - name: Stage platform packages
        run: |
          set -euo pipefail
          for platform in ${PLATFORMS.map((p) => p.key).join(' ')}; do
            dest="npm/\${platform}"
            cp "artifacts/\${platform}/index.node" "\${dest}/index.node"
            # Read the manifest the bundler wrote rather than naming libraries
            # here. A second list is a second thing to get wrong.
            while read -r lib; do
              [ -n "\$lib" ] || continue
              cp "artifacts/\${platform}/\${lib}" "\${dest}/\${lib}"
            done < "artifacts/\${platform}/bundled-libs.txt"
          done

      - name: Publish platform packages
        run: |
          set -euo pipefail
          for platform in ${PLATFORMS.map((p) => p.key).join(' ')}; do
            npm publish --provenance --access public "npm/\${platform}"
          done

      # Root last: it depends on the platform packages existing at this
      # version, so publishing it first leaves users with an install that
      # cannot resolve its own binary.
      - name: Publish ${name}
        run: npm publish --provenance --access public

  # No checkout. No toolchain. No DYLD_/LD_ variables. This job's whole value
  # is being a machine that did not build the artifact.
  consume:
    needs: publish
    strategy:
      fail-fast: false
      matrix:
        os: [${[...new Set(PLATFORMS.map((p) => p.runner))].join(', ')}]
    runs-on: \${{ matrix.os }}
    steps:
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
      - name: Assert this machine did not build the package
        run: |
          test ! -e .git || { echo "a checkout is present — this job would prove nothing"; exit 1; }
          test ! -e package.json || { echo "a project is present — this job would prove nothing"; exit 1; }
      - name: Install from the registry and run it
        env:
          VERSION: \${{ needs.publish.outputs.version }}
        run: |
          set -euo pipefail
          mkdir -p /tmp/consume && cd /tmp/consume
          npm init -y >/dev/null
          # The exact version just published, not @latest: the registry takes
          # a while to serve a new version everywhere, and @latest in that
          # window installs the PREVIOUS release and passes — proving nothing
          # about this one. Wait for it rather than racing it.
          for attempt in $(seq 1 30); do
            npm view "${name}@\${VERSION}" version >/dev/null 2>&1 && break
            echo "waiting for ${name}@\${VERSION} to appear on the registry (\${attempt}/30)"
            sleep 10
          done
          npm install "${name}@\${VERSION}"
          node -e "const a = require('${name}'); console.log('loaded:', Object.keys(a).length, 'exports');"
`;

// The scaffold runs inside a project that already exists, so it must never
// cost the author work they had. Files that are wholly ours (the loader, the
// workflow) are written only when absent, or with --force. Manifests are
// PATCHED, never replaced: by the time anyone wants prebuilds there is usually
// a name, a version, dependencies and scripts worth keeping.
function scaffoldRelease(dir, target, { force = false } = {}) {
  const created = [];
  const kept = [];
  const warnings = [];
  const readJsonIfPresent = (abs) =>
    existsSync(abs) ? JSON.parse(readFileSync(abs, 'utf8')) : null;
  const write = (rel, content, { patch = false } = {}) => {
    const abs = join(dir, rel);
    if (existsSync(abs)) {
      if (readFileSync(abs, 'utf8') === content) return;
      if (!patch && !force) {
        kept.push(join(target, rel));
        return;
      }
    }
    mkdirSync(dirname(abs), { recursive: true });
    writeFileSync(abs, content);
    created.push(join(target, rel));
  };

  const pkgPath = join(dir, 'package.json');
  const existing = readJsonIfPresent(pkgPath);
  const pkg = existing || {};
  const name = pkg.name || basename(dir);
  const version = pkg.version || '0.1.0';
  const framework = JSON.parse(
    readFileSync(join(PKG_ROOT, 'package.json'), 'utf8')
  ).version;

  pkg.name = name;
  pkg.version = version;
  if (!pkg.main) {
    pkg.main = 'index.js';
  } else if (pkg.main.replace(/^\.\//, '') !== 'index.js') {
    // Rewriting it would break whatever the author's entry point does; not
    // mentioning it leaves the loader unreachable and the prebuilds unused.
    warnings.push(
      `package.json "main" is ${JSON.stringify(pkg.main)}, so the generated loader (index.js) ` +
        `is not your entry point. Point "main" at index.js, or require('./index.js') from ${pkg.main}.`
    );
  }
  // A package with no `files` publishes the whole project; adding a list here
  // would narrow it to index.js and silently drop everything else, `main`
  // included. Only a new package, or one that already lists files, gets it.
  // NOT build/index.node: the binary ships in the platform packages, and
  // including it here would publish it twice and defeat the os/cpu split.
  if (!existing || Array.isArray(pkg.files)) {
    pkg.files = [...new Set([...(pkg.files || []), 'index.js', 'load-error.js'])];
  }
  pkg.optionalDependencies = {
    ...(pkg.optionalDependencies || {}),
    ...Object.fromEntries(PLATFORMS.map((p) => [`${name}-${p.key}`, version])),
  };
  pkg.devDependencies = { ...(pkg.devDependencies || {}), 'napi-mojo': `^${framework}` };

  // npm provenance compares repository.url with the repository the workflow
  // runs in, for the root package and every platform package alike.
  if (!pkg.repository) {
    const fromGit = repositoryFromGit(dir);
    if (fromGit) pkg.repository = fromGit;
    else {
      warnings.push(
        'package.json has no "repository", and no GitHub remote named origin was found to derive one. ' +
          '`npm publish --provenance` rejects a package whose repository.url does not match the ' +
          'repository publishing it, so add one and re-run the scaffold before releasing.'
      );
    }
  }

  // exports.toml means the CLI generates index.d.ts; the release workflow
  // regenerates it before publishing, and this is what points consumers at it.
  if (existsSync(join(dir, 'exports.toml'))) {
    pkg.types = pkg.types || 'index.d.ts';
    if (Array.isArray(pkg.files) && pkg.types === 'index.d.ts') {
      pkg.files = [...new Set([...pkg.files, 'index.d.ts'])];
    }
  }

  // npm runs the `version` script after bumping package.json and before
  // committing, so the platform manifests move in the same commit.
  const syncScript = 'napi-mojo release --sync && git add package.json npm';
  pkg.scripts = pkg.scripts || {};
  if (!pkg.scripts.version) {
    pkg.scripts.version = syncScript;
  } else if (!pkg.scripts.version.includes('release --sync')) {
    warnings.push(
      `package.json already has a "version" script, so \`npm version\` will not resync the platform ` +
        `manifests. Add \`${syncScript}\` to it, or run \`npx napi-mojo release --sync\` before each release.`
    );
  }
  write('package.json', JSON.stringify(pkg, null, 2) + '\n', { patch: true });

  const license = platformLicense(PLATFORMS[0], pkg.license);
  if (!pkg.license) {
    warnings.push(
      `package.json has no "license". The platform packages declare ${JSON.stringify(license)} — the ` +
        'napi-mojo framework and the Mojo runtime they carry — and will add yours once it is set.'
    );
  }

  write('index.js', TEMPLATE_LOADER(name));
  // Ours, not the author's: refreshed on every run so a user's addon gets the
  // current explanations. Kept even beside an author-written index.js, which
  // can require it (docs/TROUBLESHOOTING.md, "For addon authors").
  write('load-error.js', readFileSync(join(PKG_ROOT, 'load-error.js'), 'utf8'), { patch: true });
  const napiMojoLicense = readFileSync(join(PKG_ROOT, 'LICENSE'), 'utf8');
  for (const p of PLATFORMS) {
    const rel = join('npm', p.key, 'package.json');
    const manifest = readJsonIfPresent(join(dir, rel)) || {};
    write(rel, TEMPLATE_PLATFORM_PKG(p, name, version, manifest, {
      license: platformLicense(p, pkg.license),
      repository: pkg.repository,
    }), { patch: true });
    // The texts the declaration names travel with it. Ours, not the author's,
    // so always refreshed.
    const licenses = join('npm', p.key, 'licenses');
    write(join(licenses, 'NOTICE.txt'), TEMPLATE_PLATFORM_NOTICE(name, p, pkg.license), { patch: true });
    write(join(licenses, 'LICENSE.napi-mojo.txt'), napiMojoLicense, { patch: true });
    for (const f of p.licenseFiles.filter((f) => basename(f).startsWith('LICENSE.'))) {
      write(join(licenses, basename(f)), readFileSync(join(PKG_ROOT, f), 'utf8'), { patch: true });
    }
  }
  write(join('.github', 'workflows', 'release.yml'), TEMPLATE_RELEASE_WORKFLOW(name));

  // pixi refuses to install on a platform the workspace does not declare, so
  // a build job for a missing one fails at setup — and publish needs them all.
  const pixiPath = join(dir, 'pixi.toml');
  if (existsSync(pixiPath)) {
    const toml = readFileSync(pixiPath, 'utf8');
    const line = /^platforms\s*=\s*\[([^\]\n]*)\]/m.exec(toml);
    const listed = line ? [...line[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]) : null;
    const missing = listed ? PLATFORMS.map((p) => p.condaSubdir).filter((s) => !listed.includes(s)) : [];
    if (!listed) {
      warnings.push(
        `could not read "platforms" in pixi.toml; make sure it lists ${PLATFORMS.map((p) => p.condaSubdir).join(', ')}.`
      );
    } else if (missing.length) {
      const updated = [...listed, ...missing];
      writeFileSync(pixiPath, toml.replace(line[0], `platforms = [${updated.map((s) => `"${s}"`).join(', ')}]`));
      created.push(join(target, 'pixi.toml'));
      if (existsSync(join(dir, 'pixi.lock'))) {
        warnings.push(
          `added ${missing.join(', ')} to pixi.toml's platforms. Run \`pixi install\` and commit pixi.lock — ` +
            'CI installs from the lock, and a lock without these platforms fails there.'
        );
      }
    }
  }

  return { created, kept, warnings, name, version };
}

// The version npm will never serve as a real release, published under a
// dist-tag nothing installs by default.
const BOOTSTRAP_VERSION = '0.0.0-bootstrap.0';

// npm's OIDC trusted publishing can only be configured on a package that
// exists, so each package the release workflow publishes needs a first
// publish from a workstation. Publishing npm/<platform> for that — what these
// instructions used to say — pushes a package with no binary AT THE REAL
// VERSION, which can never be republished: the first CI release of that
// version then fails with E403. A placeholder avoids both problems.
function bootstrapRelease(dir, { dryRun }) {
  const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  const packages = [
    { name: pkg.name },
    ...PLATFORMS.map((p) => ({ name: `${pkg.name}-${p.key}`, os: [p.os], cpu: [p.cpu] })),
  ];
  const results = [];
  for (const target of packages) {
    const view = spawnSync('npm', ['view', target.name, 'name'], { encoding: 'utf8' });
    if (!view.error && view.status === 0 && view.stdout.trim() === target.name) {
      results.push({ name: target.name, action: 'exists' });
      continue;
    }
    if (!dryRun && !/E404|404 Not Found/.test(`${view.stderr}${view.stdout}`)) {
      fail(`could not tell whether ${target.name} exists on the registry:\n${view.stderr || view.error}`);
    }
    const stage = mkdtempSync(join(tmpdir(), 'napi-mojo-bootstrap-'));
    try {
      writeFileSync(join(stage, 'package.json'), JSON.stringify({
        name: target.name,
        version: BOOTSTRAP_VERSION,
        description: `Placeholder so ${target.name} can be configured for npm trusted publishing. Install ${pkg.name} instead.`,
        ...(target.os ? { os: target.os, cpu: target.cpu } : {}),
        ...(pkg.license ? { license: pkg.license } : {}),
        ...(pkg.repository ? { repository: pkg.repository } : {}),
      }, null, 2) + '\n');
      writeFileSync(join(stage, 'README.md'),
        `# ${target.name}\n\nPlaceholder published by \`napi-mojo release --bootstrap\`. Install \`${pkg.name}\`.\n`);
      const args = ['publish', '--access', 'public', '--tag', 'bootstrap', ...(dryRun ? ['--dry-run'] : [])];
      const res = spawnSync('npm', args, { cwd: stage, stdio: 'inherit' });
      if (res.error || res.status !== 0) {
        fail(`npm publish failed for ${target.name}${res.error ? `: ${res.error.message}` : ''}`);
      }
      results.push({ name: target.name, action: dryRun ? 'would publish' : 'published' });
    } finally {
      rmSync(stage, { recursive: true, force: true });
    }
  }
  return results;
}

function cmdRelease(argv) {
  const { opts, positional } = parseArgs(argv, [], ['--scaffold', '--force', '--sync', '--bootstrap', '--dry-run']);
  const modes = ['scaffold', 'sync', 'bootstrap'].filter((m) => opts[m]);
  if (modes.length !== 1) {
    fail('usage: napi-mojo release (--scaffold [--force] | --sync | --bootstrap [--dry-run]) [dir]');
  }
  const target = positional[0] || '.';
  const dir = resolve(target);
  if (!existsSync(dir)) fail(`${dir} does not exist`);

  if (opts.sync) {
    const { name, version, changed } = syncVersions(dir);
    for (const f of changed) console.log(`  synced  ${f}`);
    console.log(changed.length ? `\n${name}: platform versions set to ${version}.` : `${name}: already at ${version}.`);
    return;
  }

  if (opts.bootstrap) {
    for (const r of bootstrapRelease(dir, { dryRun: Boolean(opts['dry-run']) })) {
      console.log(`  ${r.action === 'exists' ? 'exists       ' : r.action.padEnd(13)} ${r.name}`);
    }
    console.log(`
Next, on npmjs.com, add a trusted publisher to EACH package above: this GitHub
repository, workflow file release.yml. Then publish a GitHub release; the
workflow publishes the real version over OIDC and moves "latest" to it.`);
    return;
  }

  const { created, kept, warnings, name, version } = scaffoldRelease(dir, target, {
    force: Boolean(opts.force),
  });
  for (const f of created) console.log(`  wrote   ${f}`);
  for (const f of kept) console.log(`  kept    ${f} (it differs from the template; pass --force to overwrite)`);
  for (const w of warnings) console.log(`\nwarning: ${w}`);
  console.log(`
Scaffolded prebuild publishing for ${name}@${version}.

Before the first release:

  1. Commit what was written above.
  2. npx napi-mojo release --bootstrap     (needs \`npm login\`)
     npm's OIDC trusted publishing can only be configured on a package that
     already exists. This publishes a placeholder (${BOOTSTRAP_VERSION}, dist-tag
     "bootstrap") for ${name} and each platform package, so no real version is
     spent on a package with no binary in it. Add --dry-run to preview.
  3. On npmjs.com, add a trusted publisher to each package: this repository,
     workflow file release.yml.

Then publish a GitHub release. \`npm version\` keeps the platform manifests in
step through the "version" script added to package.json.

When a user's require() fails on their machine (a container image without the
C++ runtime, an old glibc, Alpine), index.js explains it via load-error.js.
Point your README at https://github.com/codetalcott/napi-mojo/blob/main/docs/TROUBLESHOOTING.md`);
}

const HELP = `napi-mojo ${VERSION} — build Node.js native addons in Mojo

Usage:
  napi-mojo init <dir> [--force]        scaffold a new addon
      --host             scaffold a Mojo program hosted by Node instead
  napi-mojo generate [options]          exports.toml -> generated Mojo (+ .d.ts)
      --toml <file>      declaration file       (default: exports.toml)
      --out <dir>        generated output dir   (default: generated)
      --dts <file>       also emit TypeScript declarations from the TOML
  napi-mojo build [entry] [options]     compile the addon
      entry              main module            (default: lib.mojo)
      -o, --out <file>   output .node path      (default: build/index.node)
      --include <dir>    framework include path (default: this package's src/)
      --mojo "<cmd>"     compiler command       (default: pixi run mojo | mojo)
      --bundle           bundle Mojo runtime libs next to the .node (self-contained)
  napi-mojo run [entry] [-- <args>]     build and run a Mojo program on Node
      entry              main module            (default: main.mojo)
      --include <dir>    framework include path (default: this package's src/)
      --mojo "<cmd>"     compiler command       (default: pixi run mojo | mojo)
      --keep             keep the generated wrapper for inspection
      --rebuild          force a recompile (runs are cached on input hash)
  napi-mojo release --scaffold [dir]     add prebuild + publish setup to an addon
      (package.json optionalDependencies, npm/<platform>/, a release workflow)
      --force            overwrite an existing index.js / release.yml
  napi-mojo release --sync [dir]         set every platform manifest to package.json's version
  napi-mojo release --bootstrap [dir]    first-publish placeholders so trusted publishing
      --dry-run          can be configured (no real version is spent)
  napi-mojo --version | --help
`;

const [cmd, ...rest] = process.argv.slice(2);
switch (cmd) {
  case 'init': cmdInit(rest); break;
  case 'generate': cmdGenerate(rest); break;
  case 'build': cmdBuild(rest); break;
  case 'run': cmdRun(rest); break;
  case 'release': cmdRelease(rest); break;
  case '--version': case 'version': console.log(VERSION); break;
  case undefined: case '--help': case 'help': console.log(HELP); break;
  default: fail(`unknown command "${cmd}" (see napi-mojo --help)`);
}
