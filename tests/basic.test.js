// RED: This test will fail until src/lib.mojo is compiled into build/index.node
// and exports a hello() function returning the exact string below.
//
// Run the build first: npm run build
// Then run tests:      npm test

const addon = require('../build/index.node');

test('hello() returns the greeting string', () => {
  expect(addon.hello()).toBe('Hello from Mojo!');
});
