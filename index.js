// Platform-specific native module loader for napi-mojo
// Loads the prebuilt binary for the current platform, or falls back to a local build.
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
    module.exports = require(path.join(__dirname, 'build', 'index.node'));
  }
} else {
  // Unsupported platform — try local build
  module.exports = require(path.join(__dirname, 'build', 'index.node'));
}
