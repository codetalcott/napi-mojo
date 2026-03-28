// Basic usage: strings, numbers
// Runs against the full library build (npm run build), not hello-addon.mojo alone.
const m = require('../build/index.node');

console.log(m.hello());                  // "Hello from Mojo!"
console.log(m.greet('world'));           // "Hello, world!"
console.log(m.add(2.5, 3.7));           // 6.2
console.log(m.addInts(10, 20));          // 30
console.log(m.isPositive(42));           // true
console.log(m.strictEquals(1, 1));       // true
console.log(m.coerceToString(123));      // "123"
console.log(m.sumArgs(1, 2, 3, 4, 5));  // 15
