#!/usr/bin/env node
// napi-mojo CLI — scaffold, generate, and build Mojo native addons.
//
//   napi-mojo init <dir>       scaffold a new addon (exports.toml + fns.mojo + lib.mojo)
//   napi-mojo generate         TOML → callbacks.mojo/structs.mojo (+ optional .d.ts)
//   napi-mojo build            compile the addon to a .node (+ optional runtime bundling)
//
// The CLI wraps the same machinery this repo releases itself with:
// scripts/generate-addon.mjs, scripts/toml-dts.js, scripts/bundle-runtime.sh.
// No third-party dependencies — argument parsing is deliberately minimal.

import { spawnSync } from 'node:child_process';
import {
  existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync,
} from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

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
// pixi.toml is found from cwd upward > bare `mojo` on PATH.
function resolveMojoCmd(flagValue) {
  const cmd = flagValue || process.env.NAPI_MOJO_MOJO;
  if (cmd) return cmd.split(/\s+/);
  let dir = process.cwd();
  for (;;) {
    if (existsSync(join(dir, 'pixi.toml'))) return ['pixi', 'run', 'mojo'];
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return ['mojo'];
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
        pass
    return exports
`;

const TEMPLATE_GITIGNORE = `generated/
build/
*.node
`;

const TEMPLATE_README = `# My napi-mojo addon

\`\`\`bash
napi-mojo generate --dts index.d.ts   # exports.toml -> generated/ + index.d.ts
napi-mojo build                       # lib.mojo -> build/index.node
node -e "console.log(require('./build/index.node').greet('world'))"
\`\`\`

Declare functions in \`exports.toml\`, implement them in \`fns.mojo\`, rerun
\`napi-mojo generate\`. Requires the Mojo toolchain (the CLI uses
\`pixi run mojo\` when a pixi.toml is in scope, or \`mojo\` on PATH; override
with \`--mojo "<command>"\`).
`;

function cmdInit(argv) {
  const { opts, positional } = parseArgs(argv, [], ['--force']);
  const target = positional[0];
  if (!target) fail('usage: napi-mojo init <dir> [--force]');
  const dir = resolve(target);
  if (existsSync(dir) && readdirSync(dir).length > 0 && !opts.force) {
    fail(`${dir} exists and is not empty (pass --force to scaffold anyway)`);
  }
  mkdirSync(dir, { recursive: true });
  const files = {
    'exports.toml': TEMPLATE_EXPORTS_TOML,
    'fns.mojo': TEMPLATE_FNS_MOJO,
    'lib.mojo': TEMPLATE_LIB_MOJO,
    '.gitignore': TEMPLATE_GITIGNORE,
    'README.md': TEMPLATE_README,
  };
  for (const [name, content] of Object.entries(files)) {
    writeFileSync(join(dir, name), content);
    console.log(`  created ${join(target, name)}`);
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
  if (res.error) fail(`could not run "${mojo[0]}" (${res.error.message}) — install Mojo or pass --mojo "<command>"`);
  if (res.status !== 0) process.exit(res.status ?? 1);
  console.log(`Built ${out}`);

  if (opts.bundle) {
    const script = join(PKG_ROOT, 'scripts', 'bundle-runtime.sh');
    const bres = spawnSync('bash', [script, out], { stdio: 'inherit' });
    if (bres.status !== 0) process.exit(bres.status ?? 1);
  }
}

// --- entry --------------------------------------------------------------------

const HELP = `napi-mojo ${VERSION} — build Node.js native addons in Mojo

Usage:
  napi-mojo init <dir> [--force]        scaffold a new addon
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
  napi-mojo --version | --help
`;

const [cmd, ...rest] = process.argv.slice(2);
switch (cmd) {
  case 'init': cmdInit(rest); break;
  case 'generate': cmdGenerate(rest); break;
  case 'build': cmdBuild(rest); break;
  case '--version': case 'version': console.log(VERSION); break;
  case undefined: case '--help': case 'help': console.log(HELP); break;
  default: fail(`unknown command "${cmd}" (see napi-mojo --help)`);
}
