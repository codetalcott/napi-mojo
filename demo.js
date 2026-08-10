// napi-mojo/demo — the compiled demonstration addon.
//
// This is NOT the framework. It is the addon the napi-mojo test suite is
// built against (141 functions + 4 classes exercising the full N-API v10
// surface), shipped as prebuilt binaries so you can poke at what a
// napi-mojo-built addon looks like without a Mojo toolchain:
//
//   const demo = require('napi-mojo/demo');
//   demo.hello();          // "Hello from Mojo!"
//   await demo.asyncSum(2, 3);
//
// The framework itself is Mojo source — see require('napi-mojo').include and
// examples/codegen/ for how to build your own addon against it.
const path = require('path');

const PLATFORMS = {
  'darwin-arm64': '@napi-mojo/darwin-arm64',
  'linux-x64': '@napi-mojo/linux-x64',
};

const key = `${process.platform}-${process.arch}`;
const pkg = PLATFORMS[key];

if (pkg) {
  try {
    module.exports = require(pkg);
  } catch {
    // Platform package not installed — fall back to local build (development)
    try {
      module.exports = require(path.join(__dirname, 'build', 'index.node'));
    } catch {
      throw new Error(
        `napi-mojo/demo: No prebuilt demo binary available for ${key}.\n` +
        `Build it from source (requires Mojo): https://github.com/codetalcott/napi-mojo`
      );
    }
  }
} else {
  try {
    module.exports = require(path.join(__dirname, 'build', 'index.node'));
  } catch {
    throw new Error(
      `napi-mojo/demo: Unsupported platform ${key}.\n` +
      `Build it from source (requires Mojo): https://github.com/codetalcott/napi-mojo`
    );
  }
}
