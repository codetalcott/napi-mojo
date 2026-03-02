const addon = require('../build/index.node');

test('getNull() returns null', () => {
  expect(addon.getNull()).toBeNull();
});

test('getUndefined() returns undefined', () => {
  expect(addon.getUndefined()).toBeUndefined();
});
