const addon = require('../build/index.node');

test('doubleFloat64Array doubles each element in-place', () => {
  const arr = new Float64Array([1.0, 2.0, 3.0]);
  const result = addon.doubleFloat64Array(arr);
  expect(arr[0]).toBe(2.0);
  expect(arr[1]).toBe(4.0);
  expect(arr[2]).toBe(6.0);
});

test('doubleFloat64Array returns same array object', () => {
  const arr = new Float64Array([1.0]);
  const result = addon.doubleFloat64Array(arr);
  // The returned napi_value should be the same typed array
  expect(result[0]).toBe(2.0);
});

test('doubleFloat64Array on empty array returns without error', () => {
  const arr = new Float64Array([]);
  expect(() => addon.doubleFloat64Array(arr)).not.toThrow();
});

test('doubleFloat64Array throws on non-typedarray', () => {
  expect(() => addon.doubleFloat64Array('not an array')).toThrow();
});
