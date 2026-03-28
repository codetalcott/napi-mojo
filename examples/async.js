// Async: promises, worker threads, ThreadsafeFunction
// Runs against the full library build (npm run build), not a standalone addon.
const m = require('../build/index.node');

async function main() {
  // Compute on a worker thread, return via promise
  const doubled = await m.asyncDouble(21);
  console.log('asyncDouble(21):', doubled);  // 42

  // Resolve/reject promises
  const val = await m.resolveWith('ok');
  console.log('resolveWith:', val);          // "ok"

  try {
    await m.rejectWith('oops');
  } catch (e) {
    console.log('rejectWith caught:', e.message);  // "oops"
  }

  // Call JS from a worker thread via ThreadsafeFunction
  const values = [];
  await m.asyncProgress(5, (i) => values.push(i));
  console.log('asyncProgress:', values);     // [0, 1, 2, 3, 4]
}

main();
