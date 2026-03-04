const addon = require('../build/index.node');

test('getGlobal() returns an object', () => {
  const g = addon.getGlobal();
  expect(typeof g).toBe('object');
});

test('getGlobal() has console property', () => {
  const g = addon.getGlobal();
  expect(g.console).toBeDefined();
});

test('getGlobal() has process property', () => {
  const g = addon.getGlobal();
  expect(g.process).toBeDefined();
});
