// toml-lite.js — the single shared TOML-subset parser for both generators.
//
// generate-addon.mjs and generate-dts.js used to each carry a hand-rolled
// copy of this parser, and the copies had already diverged (the addon copy
// grew an integer branch the DTS copy never got). One format, one parser.
//
// Supported subset (deliberately small — this parses exports.toml, not
// arbitrary TOML):
//   [section] / [a.b.c] section headers
//   key = "string"            (raw passthrough — escape sequences are NOT
//                              interpreted, because values are spliced into
//                              Mojo source verbatim; a body containing \n or
//                              \" must arrive byte-identical)
//   key = "string"  # comment (trailing comments after the closing quote)
//   key = """multi
//   line"""                   (raw lines preserved, whole value trimmed)
//   key = """one-liner"""
//   key = ["a", "b"]          (elements: quoted strings or bare integers)
//   key = [                   (multi-line arrays — quote-aware, so commas
//     "a, with comma",         and # inside quoted elements are preserved)
//   ]                          # trailing comments allowed on element lines
//   key = 42                  (integer)
//   key = true / false        (real booleans)
//
// Anything else on a non-blank, non-comment line is a hard error with a line
// number. The old parsers silently dropped unrecognized lines ([[tables]],
// dotted keys, unterminated strings), which surfaced later as unrelated Mojo
// "unknown name" errors — a parse problem must fail at parse time.

'use strict';

function parseError(lineNo, msg) {
  const err = new Error(`toml-lite: line ${lineNo}: ${msg}`);
  err.tomlLine = lineNo;
  return err;
}

// Split the accumulated text of an array literal (without the outer brackets)
// into elements. Quote-aware: commas and '#' inside quoted strings are data;
// '#' outside a string starts a comment that runs to end of line.
function parseArrayElements(text, startLine) {
  const items = [];
  let cur = '';
  let inString = false;
  let sawQuote = false; // current element came from a quoted string
  let started = false;  // current element has any content

  const push = () => {
    const trimmed = cur.trim();
    if (sawQuote) {
      items.push(trimmed.slice(1, -1)); // strip the outer quotes, keep raw
    } else if (trimmed !== '') {
      if (/^[+-]?\d+$/.test(trimmed)) items.push(parseInt(trimmed, 10));
      else if (trimmed === 'true') items.push(true);
      else if (trimmed === 'false') items.push(false);
      else throw parseError(startLine, `unquoted array element "${trimmed}" (only integers, booleans, and quoted strings are supported)`);
    }
    cur = '';
    sawQuote = false;
    started = false;
  };

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      cur += ch;
      if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') {
      if (started && sawQuote === false && cur.trim() !== '') {
        throw parseError(startLine, 'unexpected quote inside unquoted array element');
      }
      inString = true;
      sawQuote = true;
      started = true;
      cur += ch;
      continue;
    }
    if (ch === '#') {
      // comment: skip to end of line
      while (i < text.length && text[i] !== '\n') i++;
      continue;
    }
    if (ch === ',') {
      push();
      continue;
    }
    if (!/\s/.test(ch)) started = true;
    cur += ch;
  }
  if (inString) throw parseError(startLine, 'unterminated string in array');
  push(); // trailing element (also tolerates trailing comma: push of '' is a no-op)
  return items;
}

function parseTOML(text) {
  const result = {};
  let current = result;

  const lines = text.split('\n');
  let i = 0;

  while (i < lines.length) {
    const lineNo = i + 1;
    const rawLine = lines[i];
    const line = rawLine.trim();
    i++;

    if (!line || line.startsWith('#')) continue;

    // Section header: [a.b.c]
    const sectionMatch = line.match(/^\[([^\[\]]+)\]$/);
    if (sectionMatch) {
      const parts = sectionMatch[1].split('.').map((p) => p.trim());
      if (parts.some((p) => !/^[A-Za-z0-9_-]+$/.test(p))) {
        throw parseError(lineNo, `invalid section name "[${sectionMatch[1]}]"`);
      }
      current = result;
      for (const part of parts) {
        if (!current[part]) current[part] = {};
        current = current[part];
      }
      continue;
    }
    if (line.startsWith('[')) {
      throw parseError(lineNo, `unsupported section syntax "${line}" (array-of-tables [[...]] and quoted section names are not supported)`);
    }

    // Key = value
    const kvMatch = line.match(/^(\w+)\s*=\s*(.*)$/);
    if (!kvMatch) {
      throw parseError(lineNo, `unrecognized line "${line}"`);
    }
    const key = kvMatch[1];
    let value = kvMatch[2].trim();

    // One-line triple-quoted string: key = """x"""
    const oneLineTriple = value.match(/^"""(.*)"""\s*(#.*)?$/);
    if (oneLineTriple) {
      current[key] = oneLineTriple[1].trim();
      continue;
    }

    // Multiline string (triple quotes)
    if (value.startsWith('"""')) {
      value = value.slice(3);
      const bodyLines = [value];
      let closed = false;
      while (i < lines.length) {
        const nextLine = lines[i];
        i++;
        if (nextLine.trim().endsWith('"""')) {
          bodyLines.push(nextLine.trim().slice(0, -3));
          closed = true;
          break;
        }
        bodyLines.push(nextLine);
      }
      if (!closed) throw parseError(lineNo, `unterminated multiline string for key "${key}"`);
      current[key] = bodyLines.join('\n').trim();
      continue;
    }

    // Single-line string, with optional trailing comment after the close
    // quote. Greedy match keeps interior quotes raw (no escape processing).
    const strMatch = value.match(/^"(.*)"\s*(#.*)?$/);
    if (strMatch) {
      current[key] = strMatch[1];
      continue;
    }
    if (value.startsWith('"')) {
      throw parseError(lineNo, `unterminated string for key "${key}"`);
    }

    // Array — possibly spanning multiple lines. Accumulate until the
    // bracket closes outside of any quoted string.
    if (value.startsWith('[')) {
      let acc = value.slice(1);
      const startLine = lineNo;
      const closesOutsideString = (s) => {
        let inStr = false;
        for (let k = 0; k < s.length; k++) {
          const ch = s[k];
          if (inStr) {
            if (ch === '"') inStr = false;
          } else if (ch === '"') inStr = true;
          else if (ch === '#') {
            // comment: skip to the end of this line, keep scanning the rest
            while (k < s.length && s[k] !== '\n') k++;
          } else if (ch === ']') return { closed: true, upTo: k };
        }
        return { closed: false, upTo: s.length };
      };
      let probe = closesOutsideString(acc);
      while (!probe.closed) {
        if (i >= lines.length) throw parseError(startLine, `unterminated array for key "${key}"`);
        acc += '\n' + lines[i];
        i++;
        probe = closesOutsideString(acc);
      }
      const inner = acc.slice(0, probe.upTo);
      current[key] = parseArrayElements(inner, startLine);
      continue;
    }

    // Strip a trailing comment from bare values
    const bare = value.replace(/\s+#.*$/, '').trim();

    // Integer
    if (/^[+-]?\d+$/.test(bare)) {
      current[key] = parseInt(bare, 10);
      continue;
    }

    // Boolean
    if (bare === 'true') { current[key] = true; continue; }
    if (bare === 'false') { current[key] = false; continue; }

    throw parseError(lineNo, `unrecognized value for key "${key}": "${value}"`);
  }

  return result;
}

module.exports = { parseTOML };
