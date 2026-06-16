#!/bin/bash

set -eEux
set -o pipefail

# CPython ABI set — single source of truth (python_abis.py, shared with
# docker-build.py). Defines PYTHON_ABI_MINORS, PYTHON_DEFAULT_VERSION, PYTHON_BUILD_GLOB.
PYTHON_ABIS_SH="$(python ./python_abis.py)"
eval "$PYTHON_ABIS_SH"

CCACHE_DIR="$(readlink -nf ccache)"
SOURCE_DIR="$(readlink -nf llvm-project/llvm)"
LLDB_SOURCE_DIR="$(readlink -nf llvm-project/lldb)"
BUILD_DIR="$(readlink -nf llvm.twostage.build)"
TARGET_DIR="$(readlink -nf llvm.twostage.bin)"
LLVM_DISTRO_CONF="$(readlink -nf twostage.cmake)"
STAGE2_COMMON="$(readlink -nf stage2-common.cmake)"
LLDB_DRIVER_SRC="$(readlink -nf lldb-multipython)"
LLDB_DRIVER_BUILD="$(readlink -nf llvm.lldb.driver.build)"
LLDB_STAGING="$(readlink -nf llvm.lldb.staging)"

if [ -n "${NO_CCACHE:-}" ]; then
    CCACHE=true
    LLVM_CCACHE_BUILD=OFF
else
    CCACHE=ccache
    LLVM_CCACHE_BUILD=ON
    mkdir -p "$CCACHE_DIR"
    export CCACHE_DIR
    cat > "$CCACHE_DIR/ccache.conf" <<'__EOF__'
max_size = 20.0G
inode_cache = false
compiler_check = %compiler% --version
__EOF__
fi

PROJECT_VERSION="$(./version_extractor.py -m cmake -d "$SOURCE_DIR")"
PYTHON_PKG_VERSION="$(./version_extractor.py -m python -d "$SOURCE_DIR")"
PARALLEL_COMPILE_JOBS="$(python -c 'from subprocess import check_output; print(max(2, int(int(check_output(["nproc"], universal_newlines=True))/2 - 2)))')"
PARALLEL_LINK_JOBS="$(python -c 'from subprocess import check_output; print(max(1, int(int(check_output(["nproc"], universal_newlines=True))/8)))')"

if [ -n "${AUDITWHEEL_POLICY:-}" -a -z "${NO_MULTIPYTHON_BUILDS:-}" ]; then
    BUILD_PYTHONS="$(ls -d $PYTHON_BUILD_GLOB 2>/dev/null || true)"
else
    BUILD_PYTHONS="$(python -c 'import sys; print(sys.exec_prefix)')"
fi

############################################################
# Build LLVM/Clang/LLD ONCE (two-stage). LLDB is no longer
# built in-tree; it is built standalone per Python below.
############################################################

rm -rf "$BUILD_DIR/"* || true
rm -rf "$TARGET_DIR/"* || true

cmake3 -G Ninja \
  -Wno-dev \
  $PROJECT_VERSION \
  -DPYTHON_PKG_VERSION="$PYTHON_PKG_VERSION" \
  -DLLVM_CCACHE_BUILD=$LLVM_CCACHE_BUILD \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -DPYTHON_HOME="$(python -c 'import sys; print(sys.exec_prefix)')" \
  -DLLVM_PARALLEL_COMPILE_JOBS="$PARALLEL_COMPILE_JOBS" \
  -DLLVM_PARALLEL_LINK_JOBS="$PARALLEL_LINK_JOBS" \
  -C "$LLVM_DISTRO_CONF" \
  -S "$SOURCE_DIR" -B "$BUILD_DIR"

ccache -z

cat <<EOF

**************************************************
STAGE 1
**************************************************

EOF

ccache -s

cmake3 --build "$BUILD_DIR" --target clang-bootstrap-deps

ccache -s

cat <<EOF

**************************************************
STAGE 2
**************************************************

EOF

HOST_TARGET=$("$BUILD_DIR"/bin/llvm-config --host-target)
STAGE1_LIB="$BUILD_DIR/lib"
STAGE2_LIB="$BUILD_DIR/tools/clang/stage2-bins/lib"
LDFLAGS="-L$STAGE2_LIB/$HOST_TARGET -L$STAGE2_LIB -L$STAGE1_LIB/$HOST_TARGET -L$STAGE1_LIB" \
LD_LIBRARY_PATH="$STAGE2_LIB/$HOST_TARGET:$STAGE2_LIB:$STAGE1_LIB/$HOST_TARGET:$STAGE1_LIB" \
cmake3 --build "$BUILD_DIR" --target stage2

ccache -s

STAGE2_BINS="$BUILD_DIR/tools/clang/stage2-bins"

############################################################
# Package the Python-version-independent wheels ONCE
# (core, core-debug, toolchain-tools, clang).
############################################################

./packager.py -S 2 -b "$BUILD_DIR" -t "$TARGET_DIR" -s "$SOURCE_DIR" \
              --project core toolchain clang

############################################################
# Build a standalone LLDB ONCE PER PYTHON against the
# already-built stage-2 LLVM/Clang, via the repo-owned
# lldb-multipython CMake driver (a foreach over LLDB_PYTHONS).
############################################################

# Single source of truth for the LLDB tool set lives in packager.py.
INSTALL_TARGETS="$(python -c 'import packager; print(";".join("install-" + t for t in packager.LLDB_TOOLS))')"

LLDB_PYTHONS=""
for python_dir in $BUILD_PYTHONS; do
    LLDB_PYTHONS="${LLDB_PYTHONS:+$LLDB_PYTHONS;}$python_dir/bin/python3"
done

rm -rf "$LLDB_DRIVER_BUILD/"* "$LLDB_STAGING/"* || true
mkdir -p "$LLDB_DRIVER_BUILD" "$LLDB_STAGING"

cmake3 -G Ninja \
  -Wno-dev \
  -S "$LLDB_DRIVER_SRC" -B "$LLDB_DRIVER_BUILD" \
  -DLLDB_PYTHONS="$LLDB_PYTHONS" \
  -DLLDB_SOURCE="$LLDB_SOURCE_DIR" \
  -DSTAGE2_COMMON="$STAGE2_COMMON" \
  -DLLVM_DIR="$STAGE2_BINS/lib/cmake/llvm" \
  -DClang_DIR="$STAGE2_BINS/lib/cmake/clang" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="$HOST_TARGET" \
  -DSTAGE1_CC="$BUILD_DIR/bin/clang" \
  -DSTAGE1_CXX="$BUILD_DIR/bin/clang++" \
  -DSTAGING_ROOT="$LLDB_STAGING" \
  -DINSTALL_TARGETS="$INSTALL_TARGETS" \
  -DPACKAGE_VENDOR="Karellen, Inc. (https://karellen.co) v$PYTHON_PKG_VERSION" \
  -DLLVM_CCACHE_BUILD="$LLVM_CCACHE_BUILD" \
  -DPARALLEL_COMPILE_JOBS="$PARALLEL_COMPILE_JOBS" \
  -DPARALLEL_LINK_JOBS="$PARALLEL_LINK_JOBS"

# The standalone LLDBs are compiled by stage-1 clang and linked against the
# stage-2 LLVM/Clang dylibs, so both lib trees must be on the loader path.
LD_LIBRARY_PATH="$STAGE2_LIB/$HOST_TARGET:$STAGE2_LIB:$STAGE1_LIB/$HOST_TARGET:$STAGE1_LIB" \
cmake3 --build "$LLDB_DRIVER_BUILD"

ccache -s

############################################################
# Package each per-Python LLDB wheel under its own
# interpreter (so the wheel gets the right cpXY ABI tag),
# then validate the full wheel set for that Python.
############################################################

OLD_PATH="$PATH"
for python_dir in $BUILD_PYTHONS; do

PATH="$python_dir/bin:$OLD_PATH"
export PATH

TAG="$(python -c 'import sys; print("cp%d%d" % sys.version_info[:2])')"

./packager.py --prestaged -t "$LLDB_STAGING/lldb-$TAG" --tools-dir "$STAGE2_BINS" \
              -s "$SOURCE_DIR"

./test-build.sh
done
