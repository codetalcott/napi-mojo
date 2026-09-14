// node spike/await_probe.cjs <case> — driver for spike/await_probe.mojo.
// Each case runs in its own process (uv_run re-entry is not something to share
// a process with). See the .mojo header for the build line and recorded result.
const util = require('util');
const fs = require('fs');
const addon = require(require('path').join(__dirname, '..', 'build', 'await_probe.node'));
const which = process.argv[2];
globalThis.__settled = false;
const mark = () => { globalThis.__settled = true; };

const producers = {
  microtask: () => Promise.resolve(1).then(mark),
  fsPromise: () => fs.promises.readFile(__filename).then(mark),
  timer: () => new Promise((r) => setTimeout(r, 0)).then(mark),
  fsCallback: () => { fs.readFile(__filename, mark); },
  timerCallback: () => { setTimeout(mark, 0); },
  // a Promise whose resolve runs in a uv callback, then reports whether the .then ran
  fsCbPromise: () => { new Promise((r) => fs.readFile(__filename, () => { globalThis.__resolvedInUv = true; r(); })).then(mark); },
};

function after(label, got) {
  const t0 = Date.now();
  setImmediate(() => setTimeout(() => {
    console.log(JSON.stringify({ case: which, label, insideCallback: got,
      settledAfterReturn: globalThis.__settled, msAfterReturn: Date.now() - t0 }));
  }, 20));
}

const cases = {
  state() {
    const a = (async () => 1)();
    const b = Promise.resolve(2);
    const c = fs.promises.readFile(__filename);
    const d = (async () => { await null; return 3; })();
    console.log(JSON.stringify({ case: which,
      asyncFnNoAwait: util.inspect(a), promiseResolve: util.inspect(b),
      fsPromise: util.inspect(c).slice(0, 30), asyncFnWithAwait: util.inspect(d) }));
  },
  pollMicrotask() { after('microtask', addon.holdAndPoll(producers.microtask, 20, 25)); },
  pollFs()        { after('fsPromise', addon.holdAndPoll(producers.fsPromise, 20, 25)); },
  pollTimer()     { after('timer', addon.holdAndPoll(producers.timer, 20, 25)); },
  scopeTop()      { after('microtask@top', addon.scopeDrain(producers.microtask, () => {})); },
  scopeImmediate(){ setImmediate(() => after('microtask@setImmediate', addon.scopeDrain(producers.microtask, () => {}))); },
  uvNowaitFs()    { after('fsPromise NOWAIT', addon.uvRun(producers.fsPromise, 2, 50)); },
  uvOnceFs()      { after('fsPromise ONCE', addon.uvRun(producers.fsPromise, 1, 50)); },
  uvOnceTimer()   { after('timer ONCE', addon.uvRun(producers.timer, 1, 50)); },
  uvOnceFsCb()    { after('fs.readFile(cb) ONCE', addon.uvRun(producers.fsCallback, 1, 50)); },
  uvOnceTimerCb() { after('setTimeout(cb) ONCE', addon.uvRun(producers.timerCallback, 1, 50)); },
  uvOnceFsCbProm(){ const got = addon.uvRun(producers.fsCbPromise, 1, 50); console.log('resolve() ran inside uv_run:', !!globalThis.__resolvedInUv, '| .then ran:', got); after('fs cb->resolve ONCE', got); },
  pollFsCb()      { after('fs.readFile(cb) poll-only', addon.holdAndPoll(producers.fsCallback, 20, 25)); },
  uvOnceTimerResolve() {
    const got = addon.uvRun(() => {
      new Promise((r) => setTimeout(() => { globalThis.__resolvedInUv = true; r(); }, 0)).then(mark);
    }, 1, 50);
    console.log('timer resolve() ran inside uv_run:', !!globalThis.__resolvedInUv, '| .then ran inside:', got);
    after('timer cb->resolve ONCE', got);
  },
  uvNowaitMicro() { after('microtask NOWAIT', addon.uvRun(producers.microtask, 2, 50)); },
};
if (cases[which]) cases[which]();
