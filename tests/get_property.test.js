const addon = require('../build/index.node');

test('getProperty({name: "Mojo"}, "name") returns "Mojo"', () => {
  expect(addon.getProperty({name: "Mojo"}, "name")).toBe("Mojo");
});

test('getProperty({x: 42}, "x") returns 42', () => {
  expect(addon.getProperty({x: 42}, "x")).toBe(42);
});

test('getProperty({}, "missing") returns undefined', () => {
  expect(addon.getProperty({}, "missing")).toBeUndefined();
});

test('getProperty() with no args throws', () => {
  expect(() => addon.getProperty()).toThrow();
});
