# m0-session: an existing Mojo library, compiled into a Node addon

`lib.mojo` exposes m0's session and grant code to JavaScript. m0 is the
application framework of [mojo-http](https://github.com/codetalcott/mojo-http);
its [PyPI wheel](https://pypi.org/project/m0/) ships the framework's Mojo
source, and `napi-mojo build -I` compiles that source unchanged. A Node service
beside an m0 application (a BFF, an admin panel, a WebSocket service) can then
check m0's session cookies and stream grants with m0's own code, instead of a
JavaScript copy of the format kept in step by hand.

## Build and check

From a checkout of this repository:

```bash
python3 -m pip download m0==0.2.0 --no-deps -d /tmp/m0
python3 -m zipfile -e /tmp/m0/m0-0.2.0-py3-none-any.whl /tmp/m0
node bin/napi-mojo.mjs build examples/m0-session/lib.mojo -I /tmp/m0/m0/_mojo \
    -o examples/m0-session/build/index.node
node --test examples/m0-session/parity.mjs
```

In your own project, the build line is `npx napi-mojo build lib.mojo -I <dir>`.
Use an m0 release gated on the Mojo your toolchain runs: the wheel records it
as `gated_mojo` in `m0/_build_info.json`. The `m0-interop` CI job runs the
steps above at a pinned m0 version, and checks `gated_mojo` first.

## API

| Export | Returns |
| --- | --- |
| `grantKeyId(key)` | the key's id: the first 8 hex characters of its SHA-256 |
| `sessionBinding(cookie)` | the grant `sb` field that binds to this cookie value |
| `verifyGrant(grant, keys, now, cookie?)` | `{ok, channel, reason}` |
| `issueSession(keys, subject, exp)` | a session cookie value signed by `keys[0]` |
| `verifySession(cookie, keys, now)` | `{ok, subject, csrf, reason}` |
| `fnv1a(text)`, `xxhash32(text, seed = 0)` | m0_core's hashes of the text's UTF-8 bytes |

- Keys are strings, read as their UTF-8 bytes. The first key signs; the rest
  only verify, which is how a key rotation is carried out.
- `now` and `exp` are whole Unix seconds. The clock is always an argument, as
  it is in m0.
- A refusal is a `reason`, in m0's words: `malformed`, `unknown key`,
  `bad signature` or `expired`, and for a grant also `no session cookie` or
  `session mismatch`.
- `verifyGrant`'s `cookie` is the session cookie's value, or `null` (or
  absent) when the request carries none. `""` is a cookie, as it is in m0.

The key ring is rebuilt on every call to keep this surface small; a service
would hold it in a class or in instance data instead.

## What `parity.mjs` checks

- An issuer written on `node:crypto` first reproduces mojo-http's pinned
  vectors, then judges the addon on them.
- 300 seeded random grants and sessions, with non-ASCII keys and cookies,
  verify the same on both sides, and `issueSession` is byte-equal to the
  oracle.
- Every refusal class, including a forgery checked before its expiry.
- m0's own refusal messages and the addon's argument checks, compared whole.
- The hashes' pinned vectors, and that text crosses as its UTF-8 bytes: a
  string past 256 bytes, an embedded NUL, a lone surrogate.

It is named without `.test.` so Jest's default match never collects it into
`npm test`, where no m0 build exists.
