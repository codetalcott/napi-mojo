// Code generator example — zero hand-written N-API callbacks
//
// Build:  cd examples/codegen && bash build.sh
// Run:    node examples/codegen/codegen.js

const m = require('./build/index.node');

// mojo_fn: pure Mojo function auto-wrapped as N-API callback
console.log(m.greet('world'));           // "Hello, world!"

// Nullable return: Optional[Float64] → number | null
console.log(m.safeDivide(10, 3));        // 3.3333...
console.log(m.safeDivide(10, 0));        // null

// Struct-to-object: JS object → Mojo struct → computed result
console.log(m.configSummary({ host: 'localhost', port: 8080 }));  // "localhost:8080"

// Type errors are thrown automatically by generated type checks
try {
  m.greet(42);  // expects string, not number
} catch (e) {
  console.log('Type error caught:', e.message);
}
