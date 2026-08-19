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

  test('buffer is rejected as a return type, with the reason', () => {
    const r = generate(
      '[functions.make_buf]\njs_name = "makeBuf"\nmojo_fn = "make_buf"\n' +
        'args = ["number"]\nreturns = "buffer"\n'
    );
    // float64array returns work because MojoFloat64Array owns a buffer JS can
    // adopt; there is no Buffer counterpart, so the alternative is a silent
    // copy — which is exactly what the zero-copy tokens exist to avoid.
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/no Mojo-owned Buffer type/);
  });

  test('float64array generates a zero-copy Span in and MojoFloat64Array out', () => {
    const r = generate(
      '[functions.scale]\njs_name = "scale"\nmojo_fn = "scale"\n' +
        'args = ["float64array", "number"]\nreturns = "float64array"\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toContain('from napi.framework.js_mojo_array import MojoFloat64Array');
    expect(out).toContain('JsTypedArray.is_typedarray(_b, env, args[0])');
    expect(out).toContain('Span[Float64](unsafe_ptr=_ta_mojo_arg0.data_ptr_float64(_b, env)');
    expect(out).toContain('return mojo_result.to_js(_b, env)');
  });

  test('async declarations are capped at 4 args', () => {
    const r = generate(
      '[functions.too_many]\njs_name = "tooMany"\nasync = true\nreturns = "number"\n' +
        'args = ["number", "number", "number", "number", "number"]\n' +
        'execute_body = """\nptr[].result = 0.0\n"""\n'
    );
    // The async data struct is fixed at 4 input fields; the sync emitter's
    // >=5-arg heap-argv path has no async counterpart.
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/async function "too_many": 5 args declared/);
  });

  test('class members are capped at 4 args', () => {
    const r = generate(
      '[classes.thing]\njs_name = "Thing"\n\n' +
        '[classes.thing.instance_methods.wide]\nreturns = "number"\n' +
        'args = ["number", "number", "number", "number", "number"]\nbody = """\nreturn arg0\n"""\n'
    );
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/class method "thing\.wide": 5 args declared/);
  });

  test('a >=5-arg sync function still emits the heap-argv path', () => {
    const r = generate(
      '[functions.sum5]\njs_name = "sum5"\nreturns = "number"\n' +
        'args = ["number", "number", "number", "number", "number"]\n' +
        'body = """\nreturn _a0\n"""\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    // Sync is the one shape that goes past 4 args, and the origin widening on
    // the alloc'd buffer is what an earlier template bug got wrong.
    expect(out).toContain('var _argv = unsafe_alloc[NapiValue](5)');
    expect(out).toContain('_argv.as_unsafe_any_origin()');
    expect(out).toContain('var _a4 = _argv[unsafe_offset=4]');
    expect(out).toContain('_argv.unsafe_free()');
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
