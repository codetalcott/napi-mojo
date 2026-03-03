const addon = require('../build/index.node');

test('asyncDouble(21) resolves to 42', async () => {
  const result = await addon.asyncDouble(21);
  expect(result).toBe(42);
});

test('asyncDouble(0) resolves to 0', async () => {
  const result = await addon.asyncDouble(0);
  expect(result).toBe(0);
});

test('asyncDouble(-5) resolves to -10', async () => {
  const result = await addon.asyncDouble(-5);
  expect(result).toBe(-10);
});

test('asyncDouble returns a thenable', () => {
  const p = addon.asyncDouble(1);
  expect(typeof p.then).toBe('function');
  expect(typeof p.catch).toBe('function');
  return p; // let Jest wait for settlement
});

test('asyncDouble with multiple concurrent calls', async () => {
  const results = await Promise.all([
    addon.asyncDouble(1),
    addon.asyncDouble(2),
    addon.asyncDouble(3),
  ]);
  expect(results).toEqual([2, 4, 6]);
});

test('asyncDouble does not block the event loop', async () => {
  let timerFired = false;
  setTimeout(() => { timerFired = true; }, 0);
  await addon.asyncDouble(5);
  // Give the timer a chance to fire
  await new Promise(resolve => setTimeout(resolve, 10));
  expect(timerFired).toBe(true);
});

test('asyncDouble() with no args throws', () => {
  expect(() => addon.asyncDouble()).toThrow();
});
