const addon = require('../build/index.node');

// --- arrayHasElement ---
test('arrayHasElement([1, 2, 3], 0) returns true', () => {
  expect(addon.arrayHasElement([1, 2, 3], 0)).toBe(true);
});

test('arrayHasElement([1, 2, 3], 5) returns false', () => {
  expect(addon.arrayHasElement([1, 2, 3], 5)).toBe(false);
});

test('arrayHasElement with sparse array', () => {
  const arr = [1, , 3]; // sparse: index 1 is empty
  expect(addon.arrayHasElement(arr, 0)).toBe(true);
  expect(addon.arrayHasElement(arr, 1)).toBe(false);
  expect(addon.arrayHasElement(arr, 2)).toBe(true);
});

test('arrayHasElement with non-array throws', () => {
  expect(() => addon.arrayHasElement(42, 0)).toThrow();
});

// --- arrayDeleteElement ---
test('arrayDeleteElement removes element (makes sparse)', () => {
  const arr = [1, 2, 3];
  const result = addon.arrayDeleteElement(arr, 1);
  // delete arr[1] makes it sparse: [1, empty, 3], length stays 3
  expect(result.length).toBe(3);
  expect(result[0]).toBe(1);
  expect(result[1]).toBeUndefined();
  expect(result[2]).toBe(3);
});

test('arrayDeleteElement with non-array throws', () => {
  expect(() => addon.arrayDeleteElement('hello', 0)).toThrow();
});
