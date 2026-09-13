// The canonical table of platforms napi-mojo ships prebuilt binaries for.
//
// WHY THIS FILE EXISTS. Adding a platform touches six places: npm/<key>/,
// the root package.json optionalDependencies, demo.js's loader map,
// sync-versions.mjs, pixi.toml's platform list, and publish.yml (build matrix,
// staging, tarball verification, and a publish step). Miss one and the failure
// is silent in the worst way — publish.yml's own comments record a broken
// linux-x64 package shipping for several releases because "the same wrong
// assumption in four places" each dropped a file.
//
// So this is the one declaration, and scripts/check-platforms.mjs asserts the
// other five agree with it. The duplication is not eliminated — YAML and CJS
// cannot import this — it is GATED, the same way check-exports-doc.mjs gates
// the export table against the docs.
//
// WHAT LIMITS THIS LIST. Not our packaging: the Mojo toolchain itself. The
// `max` conda package publishes exactly three subdirs — osx-arm64, linux-64
// and linux-aarch64. There is no osx-64 build (Intel Macs) and no win-64
// build, so a prebuild for either is not something this repo can choose to
// produce. Verify before adding an entry:
//
//   curl -sL https://conda.modular.com/max/<subdir>/repodata.json | head -c 200
//
// A 404/empty response means Mojo does not target that platform yet.

/**
 * @typedef {object} Platform
 * @property {string} key        npm platform key, `${process.platform}-${process.arch}`
 * @property {string} pkg        the scoped npm package name
 * @property {string} os         node `process.platform` value (npm "os" field)
 * @property {string} cpu        node `process.arch` value (npm "cpu" field)
 * @property {string} condaSubdir the matching conda subdir in pixi.toml platforms
 * @property {string} runner     the GitHub Actions runner label that builds it
 * @property {string} libGlob    npm "files" glob for the bundled runtime libraries
 * @property {string[]} licenseFiles  Licence texts this platform's tarball must
 *   carry, relative to the repository root. Per-platform, like `license`: the
 *   macOS package contains no GCC runtime, so shipping GPLv3 alongside a
 *   declaration that does not mention it would be misleading, not thorough.
 * @property {string} license    SPDX expression covering EVERYTHING in the tarball.
 *   Not "MIT": the prebuilt packages ship third-party runtime libraries beside
 *   index.node, and the declaration has to describe what is actually inside.
 *   It differs per platform — the Linux packages carry GCC's libstdc++ and
 *   libgcc_s, and the macOS one does not, because Mojo's runtime links the
 *   system libc++ there. licenses/NOTICE.bundle.txt is the long form.
 * @property {boolean} nativelyTestableOnPublishRunner
 *   Whether the publish job (ubuntu x64) can EXECUTE this tarball, as opposed
 *   to only checking its contents against the bundler's manifest. Each platform
 *   is still executed in its own build job, which runs on its own hardware.
 */

/** @type {Platform[]} */
export const PLATFORMS = [
  {
    key: 'darwin-arm64',
    pkg: '@napi-mojo/darwin-arm64',
    os: 'darwin',
    cpu: 'arm64',
    condaSubdir: 'osx-arm64',
    runner: 'macos-latest',
    libGlob: '*.dylib*',
    license: 'MIT AND Apache-2.0 WITH LLVM-exception',
    licenseFiles: ['licenses/NOTICE.bundle.txt', 'licenses/LICENSE.mojo-runtime.txt'],
    nativelyTestableOnPublishRunner: false,
  },
  {
    key: 'linux-x64',
    pkg: '@napi-mojo/linux-x64',
    os: 'linux',
    cpu: 'x64',
    condaSubdir: 'linux-64',
    runner: 'ubuntu-latest',
    libGlob: '*.so*',
    license: 'MIT AND Apache-2.0 WITH LLVM-exception AND GPL-3.0-or-later WITH GCC-exception-3.1',
    licenseFiles: [
      'licenses/NOTICE.bundle.txt',
      'licenses/LICENSE.mojo-runtime.txt',
      'licenses/LICENSE.gcc-runtime-gpl3.txt',
      'licenses/LICENSE.gcc-runtime-exception.txt',
    ],
    nativelyTestableOnPublishRunner: true,
  },
  {
    key: 'linux-arm64',
    pkg: '@napi-mojo/linux-arm64',
    os: 'linux',
    cpu: 'arm64',
    condaSubdir: 'linux-aarch64',
    // GitHub's public arm64 Linux runners, free for public repositories.
    // This repo is public; a private repo would need a paid larger runner or
    // a self-hosted one, so check that before assuming this label works.
    runner: 'ubuntu-24.04-arm',
    libGlob: '*.so*',
    license: 'MIT AND Apache-2.0 WITH LLVM-exception AND GPL-3.0-or-later WITH GCC-exception-3.1',
    licenseFiles: [
      'licenses/NOTICE.bundle.txt',
      'licenses/LICENSE.mojo-runtime.txt',
      'licenses/LICENSE.gcc-runtime-gpl3.txt',
      'licenses/LICENSE.gcc-runtime-exception.txt',
    ],
    nativelyTestableOnPublishRunner: false,
  },
];

/** Platform keys, sorted, for stable comparison in the gate. */
export const PLATFORM_KEYS = PLATFORMS.map((p) => p.key).sort();

/** The npm package names, sorted. */
export const PLATFORM_PKGS = PLATFORMS.map((p) => p.pkg).sort();

/**
 * Every licence text any platform ships, deduplicated — what must exist in
 * `licenses/`. Which subset a given tarball carries is `p.licenseFiles`.
 * A tarball that declares a third-party licence and does not carry its text
 * is not distributable.
 */
export const ALL_LICENSE_FILES = [
  ...new Set(PLATFORMS.flatMap((p) => p.licenseFiles)),
].sort();

/** Relative paths to each platform package manifest. */
export const PLATFORM_MANIFESTS = PLATFORMS.map((p) => `npm/${p.key}/package.json`).sort();
