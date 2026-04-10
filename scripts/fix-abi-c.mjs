#!/usr/bin/env node
// fix-abi-c.mjs — insert `abi("C")` into every `def(...) -> X` type expression
// that appears inside a `get_function[...]` or `.bitcast[...]` bracket.
//
// Background: starting with Mojo dev2026040905, `std.ffi.OwnedDLHandle.get_function`
// and related typed-bitcast paths require the function type to be annotated
// `abi("C")`. This script rewrites every affected type expression in-place.
//
// Scope filter: only `def(` occurrences that are lexically inside a
// `get_function[` or `.bitcast[` bracket region are rewritten. Actual function
// *declarations* (which start with `def name(` — note the name between `def`
// and the paren) are never touched. Parametric type params like
// `parallelize_safe[func: def(Int) capturing -> None]` are also untouched
// because the enclosing `[` belongs to a generic param list, not get_function
// or bitcast.

import fs from 'node:fs';
import path from 'node:path';

const FILES = [
  'src/napi/raw.mojo',
  'src/napi/bindings.mojo',
  'src/napi/framework/runtime.mojo',
];

function rewrite(text) {
  const insertions = []; // { pos, text }
  // Stack of bracket depths at which we entered a get_function/bitcast scope.
  const scopeStack = [];
  let bracketDepth = 0;
  let i = 0;

  while (i < text.length) {
    // Detect scope entry: `get_function[` or `.bitcast[`
    if (text.startsWith('get_function[', i)) {
      i += 'get_function['.length;
      bracketDepth++;
      scopeStack.push(bracketDepth);
      continue;
    }
    if (text.startsWith('.bitcast[', i)) {
      i += '.bitcast['.length;
      bracketDepth++;
      scopeStack.push(bracketDepth);
      continue;
    }

    const ch = text[i];

    if (ch === '[') {
      bracketDepth++;
      i++;
      continue;
    }
    if (ch === ']') {
      if (
        scopeStack.length > 0 &&
        scopeStack[scopeStack.length - 1] === bracketDepth
      ) {
        scopeStack.pop();
      }
      bracketDepth--;
      i++;
      continue;
    }

    // Inside a scope? Try to match `def(` (type expression, no name).
    if (scopeStack.length > 0 && text.startsWith('def(', i)) {
      // Walk balanced parens starting after `def(`.
      let p = i + 'def('.length;
      let parenDepth = 1;
      while (p < text.length && parenDepth > 0) {
        const c = text[p];
        if (c === '(') parenDepth++;
        else if (c === ')') parenDepth--;
        p++;
      }
      // p now points just past the closing ')' of the def argument list.
      // Skip whitespace (spaces, tabs, newlines).
      while (p < text.length && /\s/.test(text[p])) p++;

      if (text.startsWith('->', p)) {
        // Safety: skip if already annotated (idempotent re-run).
        const before = text.slice(Math.max(0, p - 20), p);
        if (!/abi\("C"\)\s*$/.test(before)) {
          insertions.push({ pos: p, text: 'abi("C") ' });
        }
      }
      // Advance one char; continue scanning inside for any nested matches.
      i++;
      continue;
    }

    i++;
  }

  // Apply insertions right-to-left so earlier offsets remain valid.
  insertions.sort((a, b) => b.pos - a.pos);
  let out = text;
  for (const ins of insertions) {
    out = out.slice(0, ins.pos) + ins.text + out.slice(ins.pos);
  }
  return { out, count: insertions.length };
}

let totalInsertions = 0;
for (const rel of FILES) {
  const abs = path.resolve(rel);
  const original = fs.readFileSync(abs, 'utf8');
  const { out, count } = rewrite(original);
  if (out !== original) {
    fs.writeFileSync(abs, out);
  }
  console.log(`${rel}: ${count} insertions`);
  totalInsertions += count;
}
console.log(`total: ${totalInsertions}`);
