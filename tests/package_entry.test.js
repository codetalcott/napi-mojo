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

  // CI installs with --omit=optional so this file exercises the binary this
  // commit BUILT, not the last published one. That flag is easy to drop, and
  // dropping it is silent: demo.js prefers an installed platform package, the
  // assertions above still pass against a stale release, and a regression in
  // the fresh build gets masked by it.
  //
  // Comparing the export SETS is what makes that visible. Any change to
  // src/exports.toml or src/addon/ moves the fresh build's surface away from
  // the published one, so a shadowing install fails here with a readable diff
  // instead of quietly testing the wrong artifact.
  test('resolves the freshly built addon, not a published one', () => {
    const built = require('../build/index.node');
    const demo = require('../demo.js');
    // getOwnPropertyNames, NOT Object.keys. napi_define_properties creates
    // non-enumerable properties by default, so Object.keys sees 5 of the 158
    // exports — the five classes — and would compare almost nothing.
    const names = (m) => Object.getOwnPropertyNames(m).sort();
    const built_ = names(built);
    const demo_ = names(demo);
    expect(built_.length).toBeGreaterThan(100);
    expect(demo_.filter((n) => !built_.includes(n))).toEqual([]);
    expect(built_.filter((n) => !demo_.includes(n))).toEqual([]);
  });
});
