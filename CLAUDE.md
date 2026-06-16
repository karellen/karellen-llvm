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
| `karellen-llvm-toolchain-tools` | llvm-ar, llvm-cov, llvm-objdump, etc. | `karellen-llvm-core` (exact version) |
| `karellen-llvm-clang` | Clang compiler infrastructure | `karellen-llvm-core` (exact version); extras: `tools` |
| `karellen-llvm-lldb` | LLDB debugger | `karellen-llvm-clang` (exact version) |

All inter-package dependencies use exact version pinning (`==`).

## Repository Layout

```
karellen-llvm/
  llvm-project/           # Git submodule → llvm/llvm-project, branch release/22.x
  patches/                # Applied to llvm-project at build time (not committed to submodule)
    001-runpath.patch      # RPATH fixes for libc++/libc++abi/libunwind/lldb
    002-llvm-tools.patch   # Adds llvm-dis to LLVM_TOOLCHAIN_TOOLS
    003-lldb-vendor.patch  # Injects LLDB_VENDOR (from PACKAGE_VENDOR) into lldb --version
  .github/workflows/
    build.yml              # CI: build → release → upload-pypi (self-hosted runner)
    update.yml             # Cron: auto-update submodule from release/22.x every 6h
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
  test-build.sh            # Validates built wheels (installs in venv, tests clang/lldb)
  check-updates.sh         # Detects upstream submodule changes
  sync-submodule-tags.sh   # Propagates submodule tags to parent repo
  upload-missing-wheels.sh # Re-uploads release wheels missing from PyPI (incomplete releases)
  patch.sh                 # Applies patches from patches/ to llvm-project
  .release                 # Release counter (integer); appended as +N local version
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
   - **Stage 2**: Use Stage 1 compiler to build the final optimized LLVM/Clang/LLD with `-O3 -glldb -DNDEBUG`, Thin LTO, Split DWARF. **LLDB is no longer built in-tree.**
3. **LLDB** is built **standalone, once per Python ABI**, by the repo-owned `lldb-multipython/` CMake driver (a `foreach` over the Python list, one `ExternalProject_Add` each) against the stage-2 LLVM/Clang dylibs, compiled by the stage-1 clang and linked to each interpreter's libpython. This avoids rebuilding LLVM/Clang for every Python. The opt/quality settings that must match between the two builds live in `stage2-common.cmake`, consumed by **both** stage 2 (via `CLANG_BOOTSTRAP_CMAKE_ARGS`) and each standalone LLDB build (via `-C`), so configuration is identical by construction. ABI-critical settings (RTTI/EH/triple/PIC) flow automatically through stage 2's exported `LLVMConfig.cmake`.
4. **`packager.py`** processes the build output into separate wheels:
   - Extracts debug symbols from ELF binaries (`llvm-objcopy --only-keep-debug`)
   - Strips debug info from release binaries (`llvm-strip -g`)
   - Generates `setup.py`/`pyproject.toml` from templates and runs `python -m build`
   - Uses `wheel-axle` (`BdistAxle`) for wheel creation with proper ABI tags

### Key Environment Variables

| Variable | Effect |
|---|---|
| `NO_CCACHE` | Disables ccache (set to any value) |
| `NO_MULTIPYTHON_BUILDS` | Build only for current Python, not all available versions |

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
- `wheels/` — Output `.whl` files
- `ccache/` — Compiler cache

## Versioning

Handled by `version_extractor.py`, which reads llvm-project git history:

- Finds the most recent `llvmorg-X.Y.Z` or `llvmorg-X.Y.Z-rcN` tag
- Appends `.postN` for N commits after the tag
- Appends `+R` if `.release` file contains R > 0 (local version segment)
- Modes: `python` (PEP 440), `cmake` (CMake defines), `tag` (git tag name), `is-tag` (boolean)

Example: tag `llvmorg-22.1.1` + 23 commits + `.release` = 0 → `22.1.1.post23`

## Patches

Patches in `patches/` are applied to `llvm-project` at build time via
`patch -d llvm-project -p1 < patches/NNN-name.patch`. They are applied in the
CI workflow's build step and also by `patch.sh`. They are **not** committed into
the submodule.

Current patches:
- `001-runpath.patch` — adds `-Wl,-rpath,'$ORIGIN'` to the libc++ shared library link
- `002-llvm-tools.patch` — adds `llvm-dis` to the default `LLVM_TOOLCHAIN_TOOLS`
- `003-lldb-vendor.patch` — adds an `LLDB_VENDOR` CMake/define hook (sourced from
  `PACKAGE_VENDOR`) so `lldb --version` shows the Karellen vendor string

When modifying patches:
- Keep them minimal and rebasing-friendly
- Number them sequentially (001, 002, ...)
- Each patch must apply cleanly against the tracked `release/22.x` branch

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
- Checks for upstream changes on `release/22.x`
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

To test wheels: `./test-build.sh` (creates a venv, installs wheels, validates)

### Adding a New Tool to Packaging

1. If it needs a new LLVM target, update `twostage.cmake`
2. Add install target to the appropriate section in `packager.py` (`TOOLCHAIN_TOOLS`, `LLDB_TOOLS`, or a new project block). `packager.LLDB_TOOLS` is the single source of truth for the LLDB tool set: `build-twostage.sh` reads it to tell the `lldb-multipython` driver which `install-<tool>` targets to build.
3. If it needs a new patch, add to `patches/` with next sequential number

### Updating Submodule Branch

When LLVM releases a new major version (e.g., 23.x):
1. Update `.gitmodules` branch to `release/23.x`
2. Update submodule: `git submodule update --remote`
3. Verify patches apply cleanly, rebase as needed
4. Test build

## Important Notes

- The `stash/` directory contains archived/legacy scripts. Do not use or reference them for current builds.
- `packager.record` is a pickled set of processed file paths, used for incremental packaging (tracking which files belong to which package). It is `.gitignore`-d.
- The packager builds the Python-independent packages in order: core → toolchain → clang. Each step records processed files and deletes them before the next step, so later packages contain only their own files. LLDB is packaged separately, once per Python, from the standalone staging dirs via `packager.py --prestaged` (using the stage-2 install for objcopy/strip via `--tools-dir`).
- LLDB wheels are Python-version-specific (contain native `.so` linked to libpython); all other wheels are `py3-none`.
- All shell scripts use `set -eEux` and `set -o pipefail` for strict error handling.
