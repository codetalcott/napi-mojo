const addon = require('../build/index.node');

// --- resolveWith tests ---

test('resolveWith(42) resolves to 42', async () => {
  const result = await addon.resolveWith(42);
  expect(result).toBe(42);
});

test('resolveWith("hello") resolves to "hello"', async () => {
  const result = await addon.resolveWith("hello");
  expect(result).toBe("hello");
});

test('resolveWith(null) resolves to null', async () => {
  const result = await addon.resolveWith(null);
  expect(result).toBeNull();
});

test('resolveWith returns a thenable', () => {
  const p = addon.resolveWith(42);
  expect(typeof p.then).toBe('function');
  expect(typeof p.catch).toBe('function');
});

test('resolveWith works with .then()', (done) => {
  addon.resolveWith(99).then(val => {
    expect(val).toBe(99);
    done();
  });
});

// --- rejectWith tests ---

test('rejectWith("oops") rejects with error message', async () => {
  await expect(addon.rejectWith("oops")).rejects.toThrow("oops");
});

test('rejectWith returns a thenable that rejects', async () => {
  const p = addon.rejectWith("fail");
  expect(typeof p.then).toBe('function');
  await expect(p).rejects.toThrow("fail");
});

test('rejectWith() with no args throws', () => {
  expect(() => addon.rejectWith()).toThrow();
});
