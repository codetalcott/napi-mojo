// Binary data: ArrayBuffer, Buffer, TypedArray, DataView
// Runs against the full library build (npm run build), not a standalone addon.
// Resolves the prebuilt platform package when installed from npm, or the
// local build/index.node in a development checkout.
const m = require('../demo');

// ArrayBuffer
const ab = m.createArrayBuffer(8);
console.log('ArrayBuffer length:', m.arrayBufferLength(ab));  // 8

// Buffer
const buf = m.createBuffer(4);
console.log('Buffer sum:', m.sumBuffer(buf));  // 0+1+2+3 = 6

// TypedArray — double each element in-place
const f64 = new Float64Array([1, 2, 3]);
m.doubleFloat64Array(f64);
console.log('Doubled Float64Array:', [...f64]);  // [2, 4, 6]

// DataView
const dvBuf = m.createArrayBuffer(16);
const dv = m.createDataView(dvBuf, 4, 8);
console.log('DataView info:', m.getDataViewInfo(dv));  // { byteLength: 8, byteOffset: 4 }

// BigInt
console.log('addBigInts:', m.addBigInts(100n, 200n));  // 300n
