// Platform-specific native module loader for napi-mojo
// Loads the prebuilt binary for the current platform, or falls back to a local build.
const path = require('path');

const PLATFORMS = {
  'darwin-arm64': '@napi-mojo/darwin-arm64',
  'linux-x64': '@napi-mojo/linux-x64',
};

const key = `${process.platform}-${process.arch}`;
const pkg = PLATFORMS[key];

let core;
if (pkg) {
  try {
    core = require(pkg);
  } catch {
    // Platform package not installed — fall back to local build (development)
    try {
      core = require(path.join(__dirname, 'build', 'index.node'));
    } catch {
      throw new Error(
        `napi-mojo: No prebuilt binary available for ${key}.\n` +
        `Prebuilt binaries are not yet distributed via npm.\n` +
        `To use napi-mojo, build from source: https://github.com/codetalcott/napi-mojo`
      );
    }
  }
} else {
  try {
    core = require(path.join(__dirname, 'build', 'index.node'));
  } catch {
    throw new Error(
      `napi-mojo: Unsupported platform ${key}.\n` +
      `To use napi-mojo, build from source: https://github.com/codetalcott/napi-mojo`
    );
  }
}

// Optional GPU addon (v0.4.0+). Compiled into build/gpu.node by build.sh
// on hosts with a GPU target; missing or fails to load on CPU-only hosts.
// Either way the core CPU API above is unaffected.
//
// Napi-mojo methods are defined via napi_define_properties, which makes them
// non-enumerable, so Object.keys / spread won't pick them up — copy via the
// getOwnPropertyNames loop to preserve every method.
let gpu;
try {
  gpu = require(path.join(__dirname, 'build', 'gpu.node'));
} catch {
  gpu = null;
}

if (gpu) {
  for (const name of Object.getOwnPropertyNames(gpu)) {
    if (name in core) continue;  // never shadow core (should never collide)
    Object.defineProperty(core, name, Object.getOwnPropertyDescriptor(gpu, name));
  }
}

module.exports = core;
