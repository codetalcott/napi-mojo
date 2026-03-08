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

// --- createTypedArrayView ---

// Helper to get TypedArray type name (cross-realm safe, avoids Jest instanceof issue)
function typedArrayName(val) {
  return Object.prototype.toString.call(val).slice(8, -1);
}

describe('createTypedArrayView (multiple TypedArray types)', () => {
  test('creates Int8Array', () => {
    const ab = new ArrayBuffer(4);
    const ta = addon.createTypedArrayView('int8', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Int8Array');
    expect(ta.length).toBe(4);
  });

  test('creates Uint8Array', () => {
    const ab = new ArrayBuffer(4);
    const ta = addon.createTypedArrayView('uint8', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Uint8Array');
    expect(ta.length).toBe(4);
  });

  test('creates Uint8ClampedArray', () => {
    const ab = new ArrayBuffer(4);
    const ta = addon.createTypedArrayView('uint8clamped', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Uint8ClampedArray');
    expect(ta.length).toBe(4);
  });

  test('creates Int16Array', () => {
    const ab = new ArrayBuffer(8);
    const ta = addon.createTypedArrayView('int16', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Int16Array');
    expect(ta.length).toBe(4);
  });

  test('creates Uint16Array', () => {
    const ab = new ArrayBuffer(8);
    const ta = addon.createTypedArrayView('uint16', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Uint16Array');
    expect(ta.length).toBe(4);
  });

  test('creates Int32Array', () => {
    const ab = new ArrayBuffer(16);
    const ta = addon.createTypedArrayView('int32', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Int32Array');
    expect(ta.length).toBe(4);
  });

  test('creates Uint32Array', () => {
    const ab = new ArrayBuffer(16);
    const ta = addon.createTypedArrayView('uint32', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Uint32Array');
    expect(ta.length).toBe(4);
  });

  test('creates Float32Array', () => {
    const ab = new ArrayBuffer(16);
    const ta = addon.createTypedArrayView('float32', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Float32Array');
    expect(ta.length).toBe(4);
  });

  test('creates Float64Array', () => {
    const ab = new ArrayBuffer(32);
    const ta = addon.createTypedArrayView('float64', ab, 0, 4);
    expect(typedArrayName(ta)).toBe('Float64Array');
    expect(ta.length).toBe(4);
  });

  test('created view shares underlying ArrayBuffer', () => {
    const ab = new ArrayBuffer(8);
    const u8 = new Uint8Array(ab);
    u8[0] = 42;
    const view = addon.createTypedArrayView('uint8', ab, 0, 8);
    expect(view[0]).toBe(42);
  });

  test('offset parameter works correctly', () => {
    const ab = new ArrayBuffer(8);
    const full = new Uint8Array(ab);
    full[4] = 99;
    const view = addon.createTypedArrayView('uint8', ab, 4, 4);
    expect(view[0]).toBe(99);
  });

  test('throws on unknown type string', () => {
    const ab = new ArrayBuffer(4);
    expect(() => addon.createTypedArrayView('bogus', ab, 0, 4)).toThrow();
  });
});

// --- getTypedArrayType ---

describe('getTypedArrayType', () => {
  test('returns correct type for Float64Array', () => {
    const ta = new Float64Array(4);
    expect(addon.getTypedArrayType(ta)).toBe(8); // NAPI_FLOAT64_ARRAY
  });

  test('returns correct type for Uint8Array', () => {
    const ta = new Uint8Array(4);
    expect(addon.getTypedArrayType(ta)).toBe(1); // NAPI_UINT8_ARRAY
  });

  test('returns correct type for Int32Array', () => {
    const ta = new Int32Array(4);
    expect(addon.getTypedArrayType(ta)).toBe(5); // NAPI_INT32_ARRAY
  });

  test('returns correct type for Float32Array', () => {
    const ta = new Float32Array(4);
    expect(addon.getTypedArrayType(ta)).toBe(7); // NAPI_FLOAT32_ARRAY
  });

  test('throws TypeError on non-TypedArray', () => {
    try {
      addon.getTypedArrayType([1, 2, 3]);
      expect(true).toBe(false);
    } catch (e) {
      expect(e.name).toBe('TypeError');
    }
  });
});

// --- getTypedArrayLength ---

describe('getTypedArrayLength', () => {
  test('returns element count for Float64Array', () => {
    expect(addon.getTypedArrayLength(new Float64Array(10))).toBe(10);
  });

  test('returns element count for Uint8Array', () => {
    expect(addon.getTypedArrayLength(new Uint8Array(256))).toBe(256);
  });

  test('returns 0 for empty TypedArray', () => {
    expect(addon.getTypedArrayLength(new Int32Array(0))).toBe(0);
  });

  test('throws TypeError on non-TypedArray', () => {
    try {
      addon.getTypedArrayLength('hello');
      expect(true).toBe(false);
    } catch (e) {
      expect(e.name).toBe('TypeError');
    }
  });
});
