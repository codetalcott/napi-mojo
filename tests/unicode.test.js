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
