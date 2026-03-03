const addon = require('../build/index.node');

test('mapArray([1,2,3], x => x * 2) returns [2,4,6]', () => {
  expect(addon.mapArray([1, 2, 3], x => x * 2)).toEqual([2, 4, 6]);
});

test('mapArray(["a","b"], s => s.toUpperCase()) returns ["A","B"]', () => {
  expect(addon.mapArray(["a", "b"], s => s.toUpperCase())).toEqual(["A", "B"]);
});

test('mapArray([], fn) returns []', () => {
  expect(addon.mapArray([], x => x)).toEqual([]);
});

test('mapArray(42, fn) throws (not an array)', () => {
  expect(() => addon.mapArray(42, x => x)).toThrow();
});

test('mapArray([1,2,3], "not a function") throws', () => {
  expect(() => addon.mapArray([1, 2, 3], "not a function")).toThrow();
});

test('mapArray propagates callback errors with handle scope cleanup', () => {
  expect(() => addon.mapArray([1, 2, 3], () => { throw new Error('fail'); })).toThrow('fail');
});

test('mapArray with 10000 elements works', () => {
  const arr = Array.from({length: 10000}, (_, i) => i);
  const result = addon.mapArray(arr, x => x + 1);
  expect(result.length).toBe(10000);
  expect(result[0]).toBe(1);
  expect(result[9999]).toBe(10000);
});
