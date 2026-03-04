const addon = require('../build/index.node');

test('createSymbol("desc") returns a symbol', () => {
  const s = addon.createSymbol('desc');
  expect(typeof s).toBe('symbol');
});

test('createSymbol result is symbol type', () => {
  const s = addon.createSymbol('test');
  expect(typeof s).toBe('symbol');
});

test('two createSymbol("desc") calls return different symbols', () => {
  const a = addon.createSymbol('desc');
  const b = addon.createSymbol('desc');
  expect(a).not.toBe(b);
});

test('symbolFor("key") returns a symbol', () => {
  const s = addon.symbolFor('key');
  expect(typeof s).toBe('symbol');
});

test('two symbolFor("key") calls return same symbol', () => {
  const a = addon.symbolFor('key');
  const b = addon.symbolFor('key');
  expect(a).toBe(b);
});
