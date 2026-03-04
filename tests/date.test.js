const addon = require('../build/index.node');

test('createDate(0) returns a Date at epoch', () => {
  const d = addon.createDate(0);
  expect(typeof d.getTime).toBe('function');
  expect(d.getTime()).toBe(0);
});

test('createDate(1709424000000) returns correct date', () => {
  const d = addon.createDate(1709424000000);
  expect(d.getTime()).toBe(1709424000000);
});

test('getDateValue(new Date(0)) returns 0', () => {
  expect(addon.getDateValue(new Date(0))).toBe(0);
});

test('getDateValue(new Date(1709424000000)) returns timestamp', () => {
  expect(addon.getDateValue(new Date(1709424000000))).toBe(1709424000000);
});

test('createDate returns a Date-like object', () => {
  const d = addon.createDate(12345);
  expect(Object.prototype.toString.call(d)).toBe('[object Date]');
});
