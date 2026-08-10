// Type definitions for the napi-mojo package entry.
//
// The framework itself is Mojo source (see `include`); this entry exposes
// the paths a build script needs. The compiled demo addon's types live at
// napi-mojo/demo (declared in build/index.d.ts, generated at publish time).

/** Directory to pass to `mojo build -I` — the root of the `napi` package. */
export const include: string;

/** Directory containing the code generators. */
export const scripts: string;

/** The TOML → Mojo trampoline generator (drive via NAPI_MOJO_TOML / NAPI_MOJO_OUT). */
export const generator: string;

/** napi-mojo package version. */
export const version: string;
