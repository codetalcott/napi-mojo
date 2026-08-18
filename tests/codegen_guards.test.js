'use strict';
// The generator's REJECTION branches — the half tests/codegen/ cannot cover.
//
// kitchen-sink.toml proves every template that emits code; a declaration the
// generator is supposed to refuse can't live there, because that file has to
// compile. Each case below emitted plausible-looking Mojo (or a plausible
// .d.ts) that failed far from its cause, which is exactly the failure mode
// the kitchen-sink gate was built to end.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const GEN = path.join(__dirname, '..', 'scripts', 'generate-addon.mjs');

// Runs the generator on `toml`, returns { code, stderr }. Never throws.
function generate(toml) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'napi-mojo-guard-'));
  fs.writeFileSync(path.join(dir, 'exports.toml'), toml);
  try {
    execFileSync(process.execPath, [GEN], {
      encoding: 'utf8',
      stdio: 'pipe',
      env: {
        ...process.env,
        NAPI_MOJO_TOML: path.join(dir, 'exports.toml'),
        NAPI_MOJO_OUT: path.join(dir, 'generated'),
      },
    });
    return { code: 0, stderr: '', dir };
  } catch (e) {
    return { code: e.status, stderr: String(e.stderr || ''), dir };
  }
}

describe('generator input guards', () => {
  test('a struct with no fields is rejected, not emitted as empty method bodies', () => {
    const r = generate('[structs.empty]\njs_name = "Empty"\n[structs.empty.fields]\n');
    // Was: struct EmptyData with `def __init__(out self, ):` and two more
    // empty bodies — three syntax errors, surfacing only at `mojo build`.
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/declares no fields/);
    expect(r.stderr).toMatch(/\[structs\.empty\.fields\]/);
  });

  test('a converting token cannot be nullable in argument position', () => {
    const r = generate(
      '[functions.maybe_add]\njs_name = "maybeAdd"\nmojo_fn = "maybe_add"\n' +
        'args = ["number", "number?"]\nreturns = "number"\n'
    );
    // Was: .d.ts advertised `arg1: number | null` while the callback called
    // JsNumber.from_napi_value on it unconditionally, so the advertised null
    // raised at runtime.
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/nullable argument type "number\?" .*is not supported/);
  });

  test("a struct type is a converting token too, so it cannot be a nullable arg", () => {
    const r = generate(
      '[structs.cfg]\njs_name = "Cfg"\n[structs.cfg.fields]\nhost = "string"\n\n' +
        '[functions.take_cfg]\njs_name = "takeCfg"\nmojo_fn = "take_cfg"\n' +
        'args = ["cfg?"]\nreturns = "number"\n'
    );
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/nullable argument type "cfg\?"/);
  });

  test("'?' stays supported on pass-through args and on return types", () => {
    const r = generate(
      '[functions.pass_any]\njs_name = "passAny"\nmojo_fn = "pass_any"\n' +
        'args = ["any?", "object?", "array?"]\nreturns = "number?"\n'
    );
    expect(r.stderr).toBe('');
    expect(r.code).toBe(0);
  });

  test('field names that collide with the converter\'s identifiers emit distinct locals', () => {
    const r = generate(
      '[structs.thing]\njs_name = "Thing"\n[structs.thing.fields]\n' +
        'obj = "number"\nval = "string"\nb = "int32"\nenv = "boolean"\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'structs.mojo'), 'utf8');
    const fromJs = out.slice(out.indexOf('def thing_from_js'), out.indexOf('def thing_to_js'));
    // The converter's own local and parameters must survive intact...
    expect(fromJs).toContain('var obj = JsObject(val)');
    // ...and every field local must be distinct from them.
    for (const f of ['obj', 'val', 'b', 'env']) {
      expect(fromJs).toContain(`var _f_${f} = `);
      expect(fromJs).not.toMatch(new RegExp(`^\\s*var ${f} = (?!JsObject)`, 'm'));
    }
    expect(fromJs).toContain('return ThingData(_f_obj, _f_val, _f_b, _f_env)');
  });
});
