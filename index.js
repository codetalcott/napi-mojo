// napi-mojo — a framework for building Node.js native addons in Mojo.
//
// napi-mojo is consumed as SOURCE, the way node-addon-api is for C++: your
// addon's `mojo build` compiles against the framework with
//
//   mojo build --emit shared-lib -I <include> your_addon.mojo -o addon.node
//
// so the package's JS entry exports paths, not a compiled binary:
//
//   const napiMojo = require('napi-mojo');
//   napiMojo.include    // pass to mojo build via -I; makes `from napi.framework...` importable
//   napiMojo.generator  // the TOML code generator (see examples/codegen/)
//   napiMojo.version
//
// The compiled demonstration addon (the binary this package's test suite runs
// against) lives behind require('napi-mojo/demo').
const path = require('path');

module.exports = {
  /** Directory to pass to `mojo build -I` — the root of the `napi` package. */
  include: path.join(__dirname, 'src'),

  /** Directory containing the code generators. */
  scripts: path.join(__dirname, 'scripts'),

  /** The TOML → Mojo trampoline generator (drive via NAPI_MOJO_TOML / NAPI_MOJO_OUT). */
  generator: path.join(__dirname, 'scripts', 'generate-addon.mjs'),

  /** napi-mojo package version. */
  version: require('./package.json').version,
};
