const addon = require('../build/index.node');

test('greet("Alice") returns "Hello, Alice!"', () => {
  expect(addon.greet("Alice")).toBe("Hello, Alice!");
});

test('greet("World") returns "Hello, World!"', () => {
  expect(addon.greet("World")).toBe("Hello, World!");
});
