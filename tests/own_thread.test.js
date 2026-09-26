'use strict';
// AsyncWork.queue runs `execute` on libuv's thread pool: four threads by
// default, shared with fs, dns.lookup, crypto and zlib. A long Mojo job there
// holds a pool thread for its whole duration, so four of them stall every
// file read in the process until one finishes. AsyncWork.queue_on_thread
// runs `execute` on a thread of its own and completes on the JS thread
// through a threadsafe function, taking the same execute and complete
// callbacks.
//
// asyncSleep and threadSleep share their data struct and both callbacks;
// the queue call is the only difference between them.
const { spawnSync } = require('child_process');
const path = require('path');

const addon = require('../build/index.node');
const ADDON = path.join(__dirname, '..', 'build', 'index.node');

// Scenarios that time the pool or end an environment run in a fresh process:
// there the pool size is fixed, and a crash at teardown is an exit status
// rather than a dead Jest worker.
function child(script) {
  return spawnSync(process.execPath, ['-e', script], {
    encoding: 'utf8',
    env: { ...process.env, UV_THREADPOOL_SIZE: '4' },
    timeout: 30000,
  });
}

// Four one-second jobs, then a file read 100 ms later: on the pool the read
// waits for a job to finish, on their own threads it does not wait at all.
const readBehindJobs = (fn) => `
  const m = require(${JSON.stringify(ADDON)});
  const fs = require('fs');
  const jobs = Array.from({ length: 4 }, () => m.${fn}(1000));
  setTimeout(() => {
    const t0 = Date.now();
    fs.readFile(${JSON.stringify(__filename)}, () => {
      const readMs = Date.now() - t0;
      Promise.all(jobs).then((values) => console.log(JSON.stringify({ readMs, values })));
    });
  }, 100);
`;

describe('long async jobs and the libuv thread pool', () => {
  // The counterfactual: without it, the next test's fast read would prove
  // nothing about where the jobs ran.
  test('four jobs on the pool stall a file read behind them', () => {
    const res = child(readBehindJobs('asyncSleep'));
    expect({ status: res.status, stderr: res.stderr }).toMatchObject({ status: 0 });
    const out = JSON.parse(res.stdout);
    expect(out.values).toEqual([1000, 1000, 1000, 1000]);
    expect(out.readMs).toBeGreaterThan(500);
  }, 30000);

  test('the same jobs on their own threads leave the pool free', () => {
    const res = child(readBehindJobs('threadSleep'));
    expect({ status: res.status, stderr: res.stderr }).toMatchObject({ status: 0 });
    const out = JSON.parse(res.stdout);
    expect(out.values).toEqual([1000, 1000, 1000, 1000]);
    expect(out.readMs).toBeLessThan(250);
  }, 30000);
});

describe('AsyncWork.queue_on_thread', () => {
  test('resolves with what complete produces', async () => {
    await expect(addon.threadSleep(5)).resolves.toBe(5);
  });

  // complete rejects through AsyncWork.reject_with_error with a null work
  // handle: there is no napi_async_work to delete on this path.
  test('rejects through the same complete callback', async () => {
    let error;
    try {
      await addon.threadSleep(-1);
    } catch (e) {
      error = e;
    }
    expect(error && error.message).toBe('sleep: ms must not be negative');
  });

  test('64 jobs in flight all resolve with their own values', async () => {
    const want = Array.from({ length: 64 }, (_, i) => i % 8);
    await expect(Promise.all(want.map((ms) => addon.threadSleep(ms)))).resolves.toEqual(want);
  });

  test('a job in flight keeps the process alive until it completes', () => {
    const res = child(`
      require(${JSON.stringify(ADDON)}).threadSleep(300).then((v) => console.log('resolved', v));
    `);
    expect({ status: res.status, stderr: res.stderr }).toMatchObject({ status: 0 });
    expect(res.stdout.trim()).toBe('resolved 300');
  }, 30000);

  // The job's thread finishes after its environment is gone. Three things
  // have to hold: the addon is still mapped (Node dlcloses a Worker's addons
  // with its environment, and only the Worker loaded this one, so
  // queue_on_thread pins the image); the thread never touches the threadsafe
  // function (Node 22 and 24 free it with the environment); and complete
  // still runs, with a null env, so the job's data is freed. sleep_complete
  // prints a marker when it sees a null env.
  test('a Worker terminated with a job in flight leaves the process healthy', () => {
    const res = child(`
      const { Worker } = require('worker_threads');
      const addon = ${JSON.stringify(ADDON)};
      const w = new Worker(
        'require(' + JSON.stringify(addon) + ').threadSleep(500);' +
        "require('worker_threads').parentPort.postMessage('started');",
        { eval: true });
      w.on('message', () => setTimeout(() => w.terminate(), 50));
      w.on('exit', () => setTimeout(() => {
        require(addon).threadSleep(10).then((v) => console.log('main still works', v));
      }, 800));
    `);
    expect({ status: res.status, stderr: res.stderr }).toMatchObject({ status: 0 });
    expect(res.stdout.trim().split('\n')).toEqual([
      'napi-mojo-sleep-completed-without-env',
      'main still works 10',
    ]);
  }, 30000);

  test('process.exit with a job in flight exits cleanly', () => {
    const res = child(`
      require(${JSON.stringify(ADDON)}).threadSleep(2000);
      setTimeout(() => process.exit(0), 50);
    `);
    expect({ status: res.status, stderr: res.stderr }).toMatchObject({ status: 0 });
  }, 30000);
});
