// Unit tests for scripts/toml-lite.js — the shared TOML-subset parser behind
// generate-addon.mjs and generate-dts.js. These are the first generator-layer
// unit tests in the repo: every case below is either a real input shape from
// src/exports.toml or a shape the old hand-rolled parsers silently mangled.

const { parseTOML } = require('../scripts/toml-lite.js');

describe('toml-lite: sections and keys', () => {
  test('dotted section paths nest', () => {
    const r = parseTOML('[functions.square]\njs_name = "square"');
    expect(r.functions.square.js_name).toBe('square');
  });

  test('deeply dotted sections ([classes.point.getters.x])', () => {
    const r = parseTOML('[classes.point.getters.x]\nreturns = "number"');
    expect(r.classes.point.getters.x.returns).toBe('number');
  });

  test('comments and blank lines are skipped', () => {
    const r = parseTOML('# header\n\n[functions.f]\n# inner\njs_name = "f"\n');
    expect(r.functions.f.js_name).toBe('f');
  });

  test('array-of-tables syntax is a hard error, not a silent no-op', () => {
    expect(() => parseTOML('[[functions.f]]\njs_name = "f"')).toThrow(/line 1/);
  });

  test('unrecognized lines are a hard error with a line number', () => {
    expect(() => parseTOML('[functions.f]\nthis is not toml')).toThrow(/line 2/);
  });
});

describe('toml-lite: strings', () => {
  test('single-line string', () => {
    expect(parseTOML('k = "v"').k).toBe('v');
  });

  test('trailing comment after closing quote (old parser stored the comment IN the value)', () => {
    expect(parseTOML('k = "add"  # two numbers').k).toBe('add');
  });

  test('interior quotes/escapes pass through raw (values are spliced into Mojo verbatim)', () => {
    expect(parseTOML('k = "print(\\"hi\\")"').k).toBe('print(\\"hi\\")');
  });

  test('one-line triple-quoted string', () => {
    expect(parseTOML('k = """return x"""').k).toBe('return x');
  });

  test('multiline string preserves per-line indentation', () => {
    const r = parseTOML('body = """\nvar a = 1\nif a:\n    a += 1\n"""');
    expect(r.body).toBe('var a = 1\nif a:\n    a += 1');
  });

  test('unterminated string is a hard error', () => {
    expect(() => parseTOML('k = "oops')).toThrow(/unterminated/);
  });

  test('unterminated multiline string is a hard error', () => {
    expect(() => parseTOML('k = """\nnever closed')).toThrow(/unterminated/);
  });
});

describe('toml-lite: arrays', () => {
  test('single-line array of strings', () => {
    expect(parseTOML('args = ["number", "string"]').args).toEqual(['number', 'string']);
  });

  test('multiline array (the shape the old parser silently turned into [])', () => {
    const r = parseTOML('imports = [\n  "from a import b",\n  "from c import d",\n]');
    expect(r.imports).toEqual(['from a import b', 'from c import d']);
  });

  test('commas inside quoted elements are preserved', () => {
    expect(parseTOML('k = ["a, b", "c"]').k).toEqual(['a, b', 'c']);
  });

  test('# inside quoted elements is data; outside it is a comment', () => {
    const r = parseTOML('k = [\n  "keep # this",  # drop this\n  "x",\n]');
    expect(r.k).toEqual(['keep # this', 'x']);
  });

  test('trailing comma tolerated, empty array works', () => {
    expect(parseTOML('k = ["a",]').k).toEqual(['a']);
    expect(parseTOML('k = []').k).toEqual([]);
  });

  test('integer elements', () => {
    expect(parseTOML('k = [1, 2, 3]').k).toEqual([1, 2, 3]);
  });

  test('unterminated array is a hard error', () => {
    expect(() => parseTOML('k = [\n  "a",')).toThrow(/unterminated array/);
  });
});

describe('toml-lite: scalars', () => {
  test('integers parse as numbers (the branch the old DTS copy never had)', () => {
    expect(parseTOML('n = 42').n).toBe(42);
    expect(parseTOML('n = -7').n).toBe(-7);
  });

  test('booleans parse as real booleans', () => {
    expect(parseTOML('async = true').async).toBe(true);
    expect(parseTOML('async = false').async).toBe(false);
  });

  test('bare values with trailing comments', () => {
    expect(parseTOML('n = 42  # answer').n).toBe(42);
    expect(parseTOML('b = true # flag').b).toBe(true);
  });

  test('unrecognized bare value is a hard error', () => {
    expect(() => parseTOML('k = maybe')).toThrow(/unrecognized value/);
  });
});

describe('toml-lite: parses the real exports.toml', () => {
  const fs = require('fs');
  const path = require('path');

  test('src/exports.toml round-trips with expected top-level shape', () => {
    const text = fs.readFileSync(path.join(__dirname, '..', 'src', 'exports.toml'), 'utf8');
    const r = parseTOML(text);
    expect(Object.keys(r.functions).length).toBeGreaterThan(0);
    expect(Array.isArray(r.extra_imports)).toBe(true);
    // The point is that the multiline array survives the parse intact, so the
    // expected count is DERIVED from the file rather than hardcoded — a magic
    // number here just has to be bumped every time an import is added, which
    // is a test that rots instead of one that guards.
    const declared = text.match(/^\s*"from addon\.\w+ import \w+",?\s*$/gm) || [];
    expect(declared.length).toBeGreaterThan(0);
    expect(r.extra_imports.length).toBe(declared.length);
    // every import line survived the multiline array intact
    for (const imp of r.extra_imports) {
      expect(imp).toMatch(/^from addon\.\w+ import \w+$/);
    }
  });
});
