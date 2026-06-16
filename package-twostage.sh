#!/bin/bash -eEux
set -o pipefail

SOURCE_DIR="$(readlink -nf llvm-project/llvm)"
BUILD_DIR="$(readlink -nf llvm.twostage.build)"
TARGET_DIR="$(readlink -nf llvm.twostage.bin)"
STAGE2_BINS="$BUILD_DIR/tools/clang/stage2-bins"
LLDB_STAGING="$(readlink -nf llvm.lldb.staging)"

# CPython ABI set — single source of truth (python_abis.py).
PYTHON_ABIS_SH="$(python ./python_abis.py)"
eval "$PYTHON_ABIS_SH"

# Python-version-independent wheels (core, core-debug, toolchain-tools, clang).
./packager.py -S 2 -b "$BUILD_DIR" -t "$TARGET_DIR" -s "$SOURCE_DIR" \
              --project core toolchain clang

# Per-Python LLDB wheels from the standalone staging dirs produced by the
# lldb-multipython driver during the build (skipped if a staging dir is absent).
if [ -n "${AUDITWHEEL_POLICY:-}" -a -z "${NO_MULTIPYTHON_BUILDS:-}" ]; then
    BUILD_PYTHONS="$(ls -d $PYTHON_BUILD_GLOB 2>/dev/null || true)"
else
    BUILD_PYTHONS="$(python -c 'import sys; print(sys.exec_prefix)')"
fi

OLD_PATH="$PATH"
for python_dir in $BUILD_PYTHONS; do
    PATH="$python_dir/bin:$OLD_PATH"
    export PATH
    TAG="$(python -c 'import sys; print("cp%d%d" % sys.version_info[:2])')"
    if [ -d "$LLDB_STAGING/lldb-$TAG" ]; then
        ./packager.py --prestaged -t "$LLDB_STAGING/lldb-$TAG" --tools-dir "$STAGE2_BINS" \
                      -s "$SOURCE_DIR"
    fi
done
