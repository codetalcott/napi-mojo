// napi-mojo/demo — the compiled demonstration addon.
//
// This is NOT the framework. It is the addon the napi-mojo test suite is
// built against (142 functions + 4 classes exercising the full N-API v10
// surface), shipped as prebuilt binaries so you can poke at what a
// napi-mojo-built addon looks like without a Mojo toolchain:
//
//   const demo = require('napi-mojo/demo');
//   demo.hello();          // "Hello from Mojo!"
//   await demo.asyncSum(2, 3);
//
// The framework itself is Mojo source — see require('napi-mojo').include and
// examples/codegen/ for how to build your own addon against it.
const fs = require('fs');
const path = require('path');
const { explainLoadError } = require('./load-error.js');

// Keep in sync with scripts/platforms.mjs — scripts/check-platforms.mjs fails
// CI if these drift. (This file is CJS and ships to consumers, so it carries
// its own copy rather than importing the table.)
const PLATFORMS = {
  'darwin-arm64': '@napi-mojo/darwin-arm64',
  'linux-arm64': '@napi-mojo/linux-arm64',
  'linux-x64': '@napi-mojo/linux-x64',
};

const key = `${process.platform}-${process.arch}`;
const pkg = PLATFORMS[key];
const local = path.join(__dirname, 'build', 'index.node');

// "Not installed" and "installed but cannot load" are different failures and
// must not share a catch. This file used to treat every require() error as
// the former, so an image missing libstdc++ was told there was no prebuilt
// binary for its platform — while the binary sat right there.
function load(id) {
  try {
    return require(id);
  } catch (err) {
    throw explainLoadError(err, { name: 'napi-mojo/demo' });
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

if (pkg && installed(pkg)) {
  module.exports = load(pkg);
} else if (fs.existsSync(local)) {
  // Platform package not installed — the local build (development).
  module.exports = load(local);
} else {
  throw new Error(
    `napi-mojo/demo: ${pkg ? `No prebuilt demo binary is installed for ${key}` : `Unsupported platform ${key}`}.\n` +
    `Build it from source (requires Mojo): https://github.com/codetalcott/napi-mojo`
  );
}
