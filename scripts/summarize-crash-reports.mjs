#!/usr/bin/env node
/**
 * summarize-crash-reports.mjs — print the macOS crash reports a job left behind.
 *
 * When a Jest worker dies in CI, all Jest can say is "terminated by another
 * process: signal=SIGSEGV". macOS's ReportCrash has meanwhile written a full
 * report — exception, faulting thread, symbolised frames — to
 * ~/Library/Logs/DiagnosticReports on a runner that is deleted minutes later.
 * This runs on failure (via .github/actions/upload-crash-reports) and puts the
 * part that matters into the job log, with frames from the addon and the Mojo
 * runtime marked `>>`.
 *
 * That distinction is the first question for any crash here. This repo shipped
 * a finalizer use-after-free that surfaced as a crash inside V8's GC with no
 * addon frame at the top (see the Guard Malloc recipe in CLAUDE.md) — so "no
 * Mojo code in the faulting thread" narrows the search, but does not clear the
 * addon on its own.
 *
 * Never fails the job: it is diagnostics for a failure that already happened.
 *
 * Usage:
 *   node scripts/summarize-crash-reports.mjs [--dir <path>] [--since-hours <n>] [--frames <n>]
 */

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const MOJO_IMAGE = /^(index\.node|.*\.node|libKGENCompilerRTShared|libAsyncRT|libMSupportGlobals)/;

function args(argv) {
  const opt = { dirs: [], sinceHours: 6, frames: 25 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--dir') opt.dirs.push(argv[++i]);
    else if (argv[i] === '--since-hours') opt.sinceHours = Number(argv[++i]);
    else if (argv[i] === '--frames') opt.frames = Number(argv[++i]);
  }
  if (!opt.dirs.length) {
    opt.dirs = [join(homedir(), 'Library/Logs/DiagnosticReports'), '/Library/Logs/DiagnosticReports'];
  }
  return opt;
}

function summarize(file, maxFrames) {
  const text = readFileSync(file, 'utf8');
  // One-line JSON header, then the JSON body.
  const newline = text.indexOf('\n');
  const body = JSON.parse(text.slice(newline + 1));
  const out = [];
  const ex = body.exception || {};
  out.push(`process   : ${body.procPath || '?'} (pid ${body.pid ?? '?'}, parent: ${body.parentProc || '?'})`);
  out.push(`captured  : ${body.captureTime || '?'}`);
  out.push(`exception : ${[ex.type, ex.signal, ex.subtype].filter(Boolean).join(' ')}` +
    (body.termination?.indicator ? `  [${body.termination.indicator}]` : ''));

  const thread = (body.threads || [])[body.faultingThread] || { frames: [] };
  const images = body.usedImages || [];
  out.push(`thread    : ${body.faultingThread}${thread.name ? ` (${thread.name})` : thread.queue ? ` (${thread.queue})` : ''}`);
  let mojoFrames = 0;
  for (const frame of (thread.frames || []).slice(0, maxFrames)) {
    const image = images[frame.imageIndex]?.name || '?';
    const mojo = MOJO_IMAGE.test(image);
    if (mojo) mojoFrames++;
    const where = frame.symbol
      ? `${frame.symbol}${frame.symbolLocation ? ` + ${frame.symbolLocation}` : ''}`
      : `0x${Number(frame.imageOffset || 0).toString(16)}`;
    out.push(`  ${mojo ? '>>' : '  '} ${image.padEnd(34)} ${where}`);
  }
  const loaded = images.filter((i) => MOJO_IMAGE.test(i.name || '')).map((i) => i.name);
  out.push(mojoFrames
    ? `verdict   : Mojo code is in the faulting thread (${mojoFrames} frame${mojoFrames === 1 ? '' : 's'} marked >>).`
    : `verdict   : no Mojo code in the faulting thread` +
      (loaded.length ? ` — but ${loaded.join(', ')} ${loaded.length === 1 ? 'was' : 'were'} loaded; a GC-time ` +
        'crash inside V8 can still be an addon finalizer\'s corruption (CLAUDE.md, Guard Malloc recipe).' : '.'));
  return out.join('\n');
}

const opt = args(process.argv.slice(2));
const cutoff = Date.now() - opt.sinceHours * 3600 * 1000;
const reports = [];
for (const dir of opt.dirs) {
  if (!existsSync(dir)) continue;
  for (const name of readdirSync(dir)) {
    if (!name.endsWith('.ips')) continue;
    const file = join(dir, name);
    try {
      if (statSync(file).mtimeMs >= cutoff) reports.push(file);
    } catch {
      // vanished or unreadable; nothing to summarise
    }
  }
}

if (!reports.length) {
  console.log(`summarize-crash-reports: no crash reports from the last ${opt.sinceHours}h in ${opt.dirs.join(', ')}.`);
  console.log('(A process killed by the runner or by Jest itself leaves none; a native fault normally does.)');
} else {
  for (const file of reports.sort()) {
    console.log(`\n=== ${file}`);
    try {
      console.log(summarize(file, opt.frames));
    } catch (e) {
      console.log(`could not parse this report: ${e.message}`);
    }
  }
}
process.exit(0);
