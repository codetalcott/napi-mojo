// The package's two JS entries:
//   require('napi-mojo')       → framework metadata (paths), node-addon-api style
//   require('napi-mojo/demo')  → the compiled demonstration addon
// Neither was covered by any test until the main entry stopped being a binary.

const fs = require('fs');
const path = require('path');

describe('package entry: napi-mojo (framework metadata)', () => {
  const entry = require('../index.js');

  test('exposes include/scripts/generator/version', () => {
    expect(typeof entry.include).toBe('string');
    expect(typeof entry.scripts).toBe('string');
    expect(typeof entry.generator).toBe('string');
    expect(entry.version).toBe(require('../package.json').version);
  });

  test('include points at the framework source root', () => {
    // -I <include> must make `from napi.framework...` importable
    expect(fs.existsSync(path.join(entry.include, 'napi', 'framework', 'register.mojo'))).toBe(true);
    expect(fs.existsSync(path.join(entry.include, 'napi', 'bindings.mojo'))).toBe(true);
  });

  test('generator path is the real generate-addon script', () => {
    expect(fs.existsSync(entry.generator)).toBe(true);
    expect(entry.generator.endsWith('generate-addon.mjs')).toBe(true);
  });

  test('the entry is NOT the compiled addon', () => {
    expect(entry.hello).toBeUndefined();
  });
});

describe('package entry: napi-mojo/demo (compiled demo addon)', () => {
  test('loads a working addon binary', () => {
    // In a dev tree this resolves the installed platform package or
    // build/index.node — either is a real demo binary; assert behavior only.
    const demo = require('../demo.js');
    expect(demo.hello()).toBe('Hello from Mojo!');
    expect(demo.add(2, 3)).toBe(5);
  });
});
