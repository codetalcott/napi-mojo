const addon = require('../build/index.node');

test('greet("héllo") returns "Hello, héllo!" (multi-byte UTF-8)', () => {
  expect(addon.greet("héllo")).toBe("Hello, héllo!");
});

test('greet("日本語") returns "Hello, 日本語!" (3-byte UTF-8 chars)', () => {
  expect(addon.greet("日本語")).toBe("Hello, 日本語!");
});

test('greet("café") returns "Hello, café!" (accented char)', () => {
  expect(addon.greet("café")).toBe("Hello, café!");
});

test('greet with emoji (4-byte UTF-8)', () => {
  expect(addon.greet("🌍")).toBe("Hello, 🌍!");
});

test('greet with multiple emoji', () => {
  expect(addon.greet("🎉🎊")).toBe("Hello, 🎉🎊!");
});

test('greet with CJK characters', () => {
  expect(addon.greet("こんにちは")).toBe("Hello, こんにちは!");
});

test('greet with large string (>4096 bytes, heap fallback)', () => {
  const big = 'x'.repeat(5000);
  expect(addon.greet(big)).toBe(`Hello, ${big}!`);
});

// Regression: JsString.from_napi_value's 256-byte fast path must not trust a
// truncated read. napi_get_value_string_utf8 truncates on a codepoint
// boundary, so a multi-byte string cut near 255 bytes reports actual in
// 252..254 — the old `actual < 255` check accepted that as complete and
// returned a silently truncated string.
test('greet with 3-byte codepoints straddling the 255-byte cut', () => {
  // 250 ASCII bytes + 3 × '€' (3 bytes each) = 259 bytes. A 256-byte buffer
  // read stops after the first '€' at 253 bytes.
  const s = 'a'.repeat(250) + '€€€';
  expect(addon.greet(s)).toBe(`Hello, ${s}!`);
});

test('greet with a 4-byte codepoint straddling the 255-byte cut', () => {
  // 252 ASCII + '🌍' (4 bytes) = 256 bytes; the read stops at 252 bytes.
  const s = 'a'.repeat(252) + '🌍';
  expect(addon.greet(s)).toBe(`Hello, ${s}!`);
});

test('greet at the stack-buffer boundary lengths (ASCII)', () => {
  for (const n of [251, 252, 253, 254, 255, 256, 300]) {
    const s = 'a'.repeat(n);
    expect(addon.greet(s)).toBe(`Hello, ${s}!`);
  }
});
