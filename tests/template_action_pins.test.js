'use strict';
// The release workflow `napi-mojo release --scaffold` writes lives inside a
// JavaScript template string in bin/napi-mojo.mjs. Dependabot bumps the
// actions in .github/workflows/ and cannot see that string, so without this
// the scaffold hands addon authors older actions than this repo runs — which
// is what happened when setup-pixi went 0.10.1 -> 0.10.2.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const USES = /uses:\s*([\w.-]+\/[\w.-]+)@(v[\w.-]+)/g;

function pins(text) {
  const out = {};
  for (const [, action, version] of text.matchAll(USES)) (out[action] ??= new Set()).add(version);
  return out;
}

test('the scaffolded release workflow pins the same action versions as this repo', () => {
  const template = fs.readFileSync(path.join(root, 'bin', 'napi-mojo.mjs'), 'utf8');
  const workflowsDir = path.join(root, '.github', 'workflows');
  const repo = pins(
    fs.readdirSync(workflowsDir).filter((f) => /\.ya?ml$/.test(f))
      .map((f) => fs.readFileSync(path.join(workflowsDir, f), 'utf8')).join('\n')
  );
  const scaffold = pins(template);
  expect(Object.keys(scaffold).length).toBeGreaterThanOrEqual(4);

  const drift = [];
  for (const [action, versions] of Object.entries(scaffold)) {
    // An action only the template uses has nothing in the repo to track.
    if (!repo[action]) continue;
    // The repo itself must agree with itself first, or "the repo's version"
    // is ambiguous.
    expect({ action, repo: [...repo[action]] }).toEqual({ action, repo: [...repo[action]].slice(0, 1) });
    const want = [...repo[action]][0];
    for (const v of versions) if (v !== want) drift.push(`${action}@${v} in the scaffold template, ${want} in .github/workflows`);
  }
  expect(drift).toEqual([]);
});
