# Karellen LLVM — Project Instructions

## Project Overview

Karellen LLVM is a downstream packager of the official LLVM project. It builds
LLVM/Clang/LLD/LLDB from source using a two-stage bootstrap compilation and
distributes the result as Python wheels on PyPI for the `manylinux_2_28_x86_64`
platform. This is **not** a PyBuilder project; it has its own bespoke build
infrastructure.

### Output Packages (PyPI)

| Package | Contents | Dependencies |
|---|---|---|
| `karellen-llvm-core` | LLVM, LTO, Remarks, libc++, libc++abi, libunwind | — |
| `karellen-llvm-core-debug` | Debug symbols for core | `karellen-llvm-core` (exact version) |
| `karellen-llvm-toolchain-tools` | llvm-ar, llvm-cov, llvm-objdump, the IR tools (`opt`, `llc`, `llvm-as`, `llvm-link`, `llvm-extract`), plus the LLVM development files: `include/llvm`, `include/llvm-c`, `lib/cmake/llvm` and `llvm-config` | `karellen-llvm-core` (exact version) |
| `karellen-llvm-clang` | Clang compiler infrastructure | `karellen-llvm-core` (exact version); extras: `tools` |
| `karellen-llvm-lldb` | LLDB debugger | `karellen-llvm-clang` (exact version) |

All inter-package dependencies use exact version pinning (`==`).

## Repository Layout

```
karellen-llvm/
  llvm-project/           # Git submodule → llvm/llvm-project, branch release/23.x
  patches/                # Applied to llvm-project at build time (not committed to submodule)
    001-runpath.patch      # RPATH fixes for libc++/libc++abi/libunwind/lldb
    002-llvm-tools.patch   # Adds llvm-dis, llvm-dwarfutil, llvm-config and the IR tools
    003-lldb-vendor.patch  # Injects LLDB_VENDOR (from PACKAGE_VENDOR) into lldb --version
    004-dev-install.patch  # Makes llvm-headers/cmake-exports installable under toolchain-only
  .github/workflows/
    build.yml              # CI: build → release → upload-pypi (self-hosted runner)
    update.yml             # Cron: auto-update submodule from release/23.x every 6h
    upload-missing.yml     # Manual: re-upload release wheels missing from PyPI
  docker-build.py          # Docker orchestration (manylinux_2_28 container)
  build-twostage.sh        # Two-stage bootstrap build script (runs inside Docker)
  package-twostage.sh      # Packaging wrapper (calls packager.py)
  packager.py              # Wheel packaging: ELF processing, debug symbol extraction, wheel generation
  version_extractor.py     # Extracts version from llvm-project git tags (llvmorg-X.Y.Z format)
  python_abis.py           # Single source of truth for the CPython ABI set; importable + emits shell
  twostage.cmake           # CMake cache file for two-stage build configuration
  stage2-common.cmake      # Shared opt/quality cache settings for stage 2 AND standalone LLDB
  lldb-multipython/        # Repo-owned CMake driver: standalone LLDB per Python (ExternalProject foreach)
  test-build.sh            # Validates built wheels (venv install; clang/lldb; dev-files smoke test)
  tests/                   # All test material
    test_packager.py        # Unit tests for packager.py
    test_version_extractor.py # Unit tests for the versioning scheme
    dev-smoke/              # Out-of-tree LLVM consumer built by test-build.sh against the wheels
  check-updates.sh         # Detects upstream submodule changes
  sync-submodule-tags.sh   # Propagates submodule tags to parent repo
  upload-missing-wheels.sh # Re-uploads release wheels missing from PyPI (incomplete releases)
  patch.sh                 # Applies patches from patches/ to llvm-project
  .release                 # Packager release counter (integer); 4th component of the release segment
  requirements.txt         # Python build deps: pyelftools, wheel-axle, setuptools, build
  stash/                   # Archived/legacy scripts (not part of active build)
```

## Build System

### Architecture

This project does **not** use PyBuilder, setuptools, or any standard Python
build system at the top level. The build is orchestrated by custom scripts:

1. **`docker-build.py`** launches a Docker container (`ghcr.io/karellen/manylinux_2_28_x86_64`)
2. Inside the container, **`build-twostage.sh`** runs a two-stage Clang bootstrap **once**:
   - **Stage 1**: Build a minimal compiler with `-O2 -g0` (no debug info)
   - **Stage 2**: Use Stage 1 compiler to build the final optimized LLVM/Clang/LLD with `-O3 -g -DNDEBUG`, Thin LTO, Split DWARF. **LLDB is no longer built in-tree.**
3. **LLDB** is built **standalone, once per Python ABI**, by the repo-owned `lldb-multipython/` CMake driver (a `foreach` over the Python list, one `ExternalProject_Add` each) against the stage-2 LLVM/Clang dylibs, compiled by the stage-1 clang and linked to each interpreter's libpython. This avoids rebuilding LLVM/Clang for every Python. The opt/quality settings that must match between the two builds live in `stage2-common.cmake`, consumed by **both** stage 2 (via `CLANG_BOOTSTRAP_CMAKE_ARGS`) and each standalone LLDB build (via `-C`), so configuration is identical by construction. ABI-critical settings (RTTI/EH/triple/PIC) flow automatically through stage 2's exported `LLVMConfig.cmake`.
4. **`packager.py`** processes the build output into separate wheels:
   - Extracts debug symbols from ELF binaries (`llvm-objcopy --only-keep-debug`)
   - Optimizes the extracted DWARF (`llvm-dwarfutil`, GC + ODR dedup) to collapse
     ThinLTO's cross-module debug-info duplication — ~42% off the core debug wheel.
     Must run before `--add-gnu-debuglink`, which CRCs the debug file
   - Strips debug info from release binaries (`llvm-strip -g`)
   - Generates `setup.py`/`pyproject.toml` from templates and runs `python -m build`
   - Uses `wheel-axle` (`BdistAxle`) for wheel creation with proper ABI tags

### Key Environment Variables

| Variable | Effect |
|---|---|
| `NO_CCACHE` | Disables ccache (set to any value) |
| `NO_MULTIPYTHON_BUILDS` | Build only for current Python, not all available versions |
| `NO_DWARF_OPT` | Skips the `llvm-dwarfutil` DWARF optimization pass in `packager.py` (that pass costs ~200 s and ~37 GB of RSS on `libLLVM`) |

### Docker Build Image

`ghcr.io/karellen/manylinux_2_28_x86_64:latest` with:
- ccache 4.13.6, cmake 4.3.3, ninja 1.13.2 (installed at container startup)
- Python 3.9–3.14 via manylinux `/opt/python/cp3{9..14}-*-shared` directories

### CMake Configuration (`twostage.cmake`)

- **Projects**: clang, clang-tools-extra, lld (LLDB is built standalone, not in-tree — see `lldb-multipython/`)
- **Runtimes**: compiler-rt, libcxx, libcxxabi, libunwind
- **Targets**: Native only
- **Defaults**: libc++ stdlib, lld linker, compiler-rt runtime, libunwind
- Stage 2 produces dynamic libraries (`LLVM_BUILD_LLVM_DYLIB`, `LLVM_LINK_LLVM_DYLIB`, `CLANG_LINK_CLANG_DYLIB`)

### Build Directories

These are ephemeral and `.gitignore`-d:
- `llvm.twostage.build/` — Stage 1 CMake/Ninja build tree
- `llvm.twostage.build.manylinux2014/` — Docker-mapped build directory
- `llvm.twostage.bin/` — Installation/staging for packaging
- `llvm.twostage.bin.debug/` — Debug symbol staging
- `llvm.lldb.driver.build/` — lldb-multipython driver build tree (per-Python LLDB ExternalProjects)
- `llvm.lldb.staging/` — per-Python standalone LLDB installs (`lldb-cpXY/`), consumed by the packager
- `venv-cpXY/`, `dev-smoke.build-cpXY/` — per-Python validation venv and dev-files smoke-test build tree, created by `test-build.sh`
- `wheels/` — Output `.whl` files
- `ccache/` — Compiler cache

## Versioning

Handled by `version_extractor.py`, which reads llvm-project git history:

- Finds the most recent `llvmorg-X.Y.Z` or `llvmorg-X.Y.Z-rcN` tag
- Appends `.postN` for N commits after the tag
- Inserts `.R` after the patch component if the `.release` file contains R > 0
- Modes: `python` (PEP 440), `cmake` (CMake defines), `tag` (git tag name), `is-tag` (boolean),
  `base` (the `X.Y.Z` that scopes `.release`)

Examples: tag `llvmorg-22.1.1` + 23 commits + `.release` = 0 → `22.1.1.post23`;
with `.release` = 1 → `22.1.1.1.post23`; on an rc tag → `22.1.1.1rc3.post23`.

### The `.release` Counter

`.release` is the **packager** release counter: it distinguishes rebuilds of the same
upstream source when only this repository's packaging changed. It is the 4th component
of the PEP 440 release segment, so the segment is the tuple
`(major, minor, patch, release)` compared lexicographically. `R = 0` emits nothing, so
the common case is byte-identical to the old output.

**Reset rule: `.release` goes back to 0 when X, Y or Z is bumped.** The counter
outranks `.postN`, so leaving it set across a bump makes the next upstream commit
produce a version that sorts *below* the previous release
(`23.1.1.post3` < `23.1.0.1.post46`).

`update.yml` performs that reset, because it is what moves the submodule: it captures
`version_extractor.py -m base` before and after the update and, when the `X.Y.Z`
differs, rewrites `.release` to `0` in the auto-update commit.

Comparing on `X.Y.Z` also settles the rc case: `rc1` → `rc2` and `rc3` → final all
leave the base at `23.1.0`, so no reset fires and the counter is carried through.

**That carry is required, not incidental — do not "fix" it.** The release segment is
compared *before* the pre-release marker, so `23.1.0.1`-anything outranks
`23.1.0`-anything; dropping the `.1` loses more than advancing the rc gains. Resetting
on an rc transition moves the version backwards every time:

| Transition | Before | After a reset | |
|---|---|---|---|
| rc1 → rc2 | `23.1.0.1rc1.post5` | `23.1.0rc2` | backwards |
| rc2 → rc3 | `23.1.0.1rc2.post9` | `23.1.0rc3` | backwards |
| rc3 → final | `23.1.0.1rc3.post80` | `23.1.0` | backwards |

This is *not* a counterexample to the ordinary `23.1.0rc3 < 23.1.0` rule, which holds
only within an identical release segment: `23.1.0.1rc3` is "rc3 of `23.1.0.1`", not
"rc3 of `23.1.0`", so the rc marker is never reached in the comparison.

A counter that reset on every tag change would have to sit *below* the pre-release
marker, which means sharing `.postN` with the commit count (`post = commits*1000 + R`).
That ordering does hold, but it inflates every published version number permanently, so
it was not adopted.

The cost of the scheme as built is only that the counter does not return to 0 until
X.Y.Z moves — during a long rc series it stays set after the packaging fix that
motivated it is ancient history. That is stale-looking, not incorrect.

A submodule bump done by hand (the "Updating Submodule Branch" procedure below) is not
covered by that workflow — reset `.release` to `0` as part of it.

`tests/test_version_extractor.py` covers the emitted versions, the `base` detection
semantics, and the ordering invariants above.

Two alternatives were evaluated and rejected; do not reintroduce them:

- **Local version (`+R`, the previous scheme).** PyPI *must* reject local versions —
  "As the Python Package Index is intended solely for indexing and hosting upstream
  projects, it MUST NOT allow the use of local version identifiers" — and it indexes on
  the public part, which for `23.1.0.post45+1` is `23.1.0.post45`, colliding with what is
  already published. `twine check --strict` passes on such a wheel, so the failure only
  surfaces at upload, after the whole build.
- **Wheel build tag (`...-23.1.0.post45-1-py3-none-...`).** Valid, accepted by PyPI, and
  correct for genuine rebuilds — but pip treats the build tag as a *selection*
  tie-breaker, not an *upgrade* trigger. An existing install of the same version reports
  "Requirement already satisfied" under `pip install -U`, so new content never reaches
  anyone who already installed that version.

There is no PEP 440 slot below `.postN` that would work: the grammar allows only `.devN`,
which marks the version a pre-release that pip skips without `--pre`, and `+local`.

## Patches

Patches in `patches/` are applied to `llvm-project` at build time via
`patch -d llvm-project -p1 < patches/NNN-name.patch`. They are applied in the
CI workflow's build step and also by `patch.sh`. They are **not** committed into
the submodule.

Current patches:
- `001-runpath.patch` — adds `-Wl,-rpath,'$ORIGIN'` to the libc++ and libc++abi
  shared library links, and extra `$ORIGIN`-relative `INSTALL_RPATH` entries to the
  LLDB Python wrapper library (`add_python_wrapper` in `lldb/bindings/python`)
- `002-llvm-tools.patch` — adds `llvm-dis`, `llvm-dwarfutil`, `llvm-config` and the
  IR tools (`opt`, `llc`, `llvm-as`, `llvm-link`, `llvm-extract`) to the default
  `LLVM_TOOLCHAIN_TOOLS`. Anything added here is also exported by
  `LLVMExports.cmake`, so it must be packaged — see `004-dev-install.patch`
- `003-lldb-vendor.patch` — adds an `LLDB_VENDOR` CMake/define hook (sourced from
  `PACKAGE_VENDOR`) so `lldb --version` shows the Karellen vendor string
- `004-dev-install.patch` — under `LLVM_INSTALL_TOOLCHAIN_ONLY` upstream skips the
  `llvm-headers` and `cmake-exports` install rules outright, so the
  `install-llvm-headers` and `install-cmake-exports` targets do not exist. The patch
  marks those rules `EXCLUDE_FROM_ALL` instead: the components stay installable on
  demand while the default `install` target is byte-for-byte unchanged. It also adds
  `acc_gen`, `analysis_gen` and `vt_gen` to the `llvm-headers` dependencies —
  upstream lists only three of the six tablegen targets that emit installed headers,
  and `install(DIRECTORY)` copies whatever exists, so a missing one silently yields
  a header set that does not compile

When modifying patches:
- Keep them minimal and rebasing-friendly
- Number them sequentially (001, 002, ...)
- Each patch must apply cleanly against the tracked `release/23.x` branch

## CI/CD

### `build.yml` — Build & Release Pipeline

- **Triggers**: PRs to master, pushes to master
- **Timeout**: 23 hours (LLVM builds are very long)
- **Runner**: self-hosted
- **Jobs**:
  1. `build`: checkout (recursive submodules, full history), apply patches, run `docker-build.py -m build`, validate with `twine check --strict`, extract the version into `$GITHUB_OUTPUT` (`python_pkg_version`), sync submodule tags (master only), upload wheels as an artifact
  2. `release` (master only): download the wheels artifact, create GitHub release with `gh release create "v$(version)" --generate-notes`
  3. `upload-pypi` (master only): download wheels from the GitHub release (`gh release download`), upload to PyPI via twine with `--skip-existing` (3 retries)

### `update.yml` — Automatic Submodule Updates

- **Schedule**: every 6 hours + manual dispatch
- Cleans up stale auto-update branches
- Checks for upstream changes on `release/23.x`
- Handles tag flips (new release tags on existing commits)
- Creates auto-update PR (`auto-update-{old}-{new}`) and auto-merges

### `upload-missing.yml` — Backfill Missing PyPI Wheels

- **Trigger**: manual (`workflow_dispatch`), with a `release_limit` input (default 10)
- Runs `upload-missing-wheels.sh`, which scans the most recent GitHub releases and
  re-uploads any wheels present on the release but missing from PyPI. Only processes
  **incomplete** releases (some but not all wheels already on PyPI); releases with
  nothing on PyPI are skipped. Supports `DRY_RUN` for a no-upload preview.

## Workflow

This is an origin repo (no upstream remote). Follow the standard workflow from
the global CLAUDE.md: branch from master, commit, push, PR to master. Never push
directly to master.

### Local Development

To build locally: `./docker-build.py -m build` (requires Docker). The build takes
many hours. Use `NO_CCACHE=1` to disable caching, `NO_MULTIPYTHON_BUILDS=1` to
build for only the current Python version.

To re-package without rebuilding: `./docker-build.py -m package`

To test wheels: `./test-build.sh` (creates a venv, installs wheels, validates clang and
lldb, then configures/builds/runs `tests/dev-smoke/` against the installed headers, CMake
package and libLLVM, and round-trips IR through `llvm-as`/`llvm-extract`/`llvm-link`/
`opt`/`llvm-dis`/`llc`).

To test the packaging and versioning logic: `python -m unittest discover -s tests -t .`
(no build required; `-t .` puts the repository root on `sys.path` so the tests can
import `packager` and `version_extractor`).

### Adding a New Tool to Packaging

1. If it needs a new LLVM target, update `twostage.cmake`
2. Add install target to the appropriate section in `packager.py` (`TOOLCHAIN_TOOLS`, `LLDB_TOOLS`, or a new project block). `packager.LLDB_TOOLS` is the single source of truth for the LLDB tool set: `build-twostage.sh` reads it to tell the `lldb-multipython` driver which `install-<tool>` targets to build.
3. If it needs a new patch, add to `patches/` with next sequential number
4. **Any tool in `LLVM_TOOLCHAIN_TOOLS` must also be in `packager.TOOLCHAIN_TOOLS`.** Every such tool is an imported target in `LLVMExports.cmake`, and a generated CMake exports file ends in a loop that `message(FATAL_ERROR)`s on a missing file — so one unpackaged tool breaks `find_package(LLVM)` for every consumer. `Packager.verify_cmake_exports` enforces this at packaging time and fails the build with the offending target names; when upstream adds a tool to `LLVM_TOOLCHAIN_TOOLS`, that is the error you will see. Note `llvm-mt` is conditional on `LLVM_ENABLE_LIBXML2`, which the current build image does not satisfy — if the image ever gains libxml2, `llvm-mt` becomes an exported target and has to be added.

### Updating Submodule Branch

When LLVM releases a new major version (e.g., 24.x):
1. Update `.gitmodules` branch to `release/24.x`
2. Update submodule: `git submodule update --remote`
3. Reset `.release` to `0` — X.Y.Z has changed, and this path bypasses the reset
   `update.yml` does automatically (see "The `.release` Counter")
4. Verify patches apply cleanly, rebase as needed
5. Test build

## Important Notes

- The `stash/` directory contains archived/legacy scripts. Do not use or reference them for current builds.
- `packager.record` is a pickled set of processed file paths, used for incremental packaging (tracking which files belong to which package). It is `.gitignore`-d.
- The `toolchain` step installs the `llvm-headers` and `cmake-exports` components (`packager.TOOLCHAIN_DEV_COMPONENTS`) on top of the tools. This must run against a **fully built** stage 2: `install(DIRECTORY)` copies whatever generated headers happen to exist and does not fail on absent ones, so packaging a partially built tree would silently ship an incomplete header set.
- The packager builds the Python-independent packages in order: core → toolchain → clang. Each step records processed files and deletes them before the next step, so later packages contain only their own files. LLDB is packaged separately, once per Python, from the standalone staging dirs via `packager.py --prestaged` (using the stage-2 install for objcopy/strip/dwarfutil via `--tools-dir`).
- LLDB wheels are Python-version-specific (contain native `.so` linked to libpython); all other wheels are `py3-none`.
- All shell scripts use `set -eEux` and `set -o pipefail` for strict error handling.
