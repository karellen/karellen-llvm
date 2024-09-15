#!/bin/bash

set -eEux
set -o pipefail

CCACHE_DIR="$(readlink -nf ccache)"
SOURCE_DIR="$(readlink -nf llvm-project/llvm)"
LLVM_BUILD_DIR="$(readlink -nf llvm.twostage.build)"
BUILD_DIR="$(readlink -nf lldb.build)"
TARGET_DIR="$(readlink -nf lldb.bin)"
LLDB_CONF="$(readlink -nf lldb.cmake)"

if [ -n "${NO_CCACHE:-}" ]; then
    CCACHE=true
    LLVM_CCACHE_BUILD=OFF
else
    CCACHE=ccache
    LLVM_CCACHE_BUILD=ON
    mkdir -p "$CCACHE_DIR"
    export CCACHE_DIR
    cat > "$CCACHE_DIR/ccache.conf" <<'__EOF__'
max_size = 9.0G
inode_cache = false
compiler_check = %compiler% --version
__EOF__
fi

rm -rf "$BUILD_DIR/"* || true
rm -rf "$TARGET_DIR/"* || true

grep "set(BOOTSTRAP_\|set(PACKAGE_VENDOR\|set(LLVM_TARGETS_TO_BUILD" twostage.cmake  | sed 's/BOOTSTRAP_//' | grep -v "set(LLVM_ENABLE_LLD"> "$LLDB_CONF"
cat >> "$LLDB_CONF" <<EOF
set(LLDB_BUILT_STANDALONE TRUE CACHE BOOL "")
set(LLVM_DIR "$(readlink -nf llvm.twostage.build/lib/cmake/llvm)" CACHE STRING "")
set(LLVM_USE_LINKER "lld" CACHE STRING "")
set(LLVM_ENABLE_IDE TRUE CACHE BOOL "")
EOF

PARALLEL_COMPILE_JOBS="$(python -c 'from subprocess import check_output; print(max(2, int(int(check_output(["nproc"], universal_newlines=True))/2 - 2)))')"
PARALLEL_LINK_JOBS="$(python -c 'from subprocess import check_output; print(max(1, int(int(check_output(["nproc"], universal_newlines=True))/8)))')"

export CC=clang
export CXX=clang++
cmake3 \
  -G Ninja \
  -Wno-dev \
  -DLLVM_ENABLE_PROJECTS="lldb" \
  -DLLVM_CCACHE_BUILD=$LLVM_CCACHE_BUILD \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -DPYTHON_HOME="/home/arcivanov/.pyenv/versions/3.12.5" \
  -DPYTHON_EXECUTABLE="/home/arcivanov/.pyenv/versions/3.12.5/bin/python3" \
  -DPython3_EXECUTABLE="/home/arcivanov/.pyenv/versions/3.12.5/bin/python3" \
  -DLLVM_PARALLEL_COMPILE_JOBS="$PARALLEL_COMPILE_JOBS" \
  -DLLVM_PARALLEL_LINK_JOBS="$PARALLEL_LINK_JOBS" \
  -C "$LLDB_CONF" \
  -S "$SOURCE_DIR" -B "$BUILD_DIR"

ccache -z

ccache -s

./patch_rules.py "$BUILD_DIR"/CMakeFiles/rules.ninja

pushd "$BUILD_DIR"
HOST_TARGET=$($LLVM_BUILD_DIR/bin/llvm-config --host-target)
STAGE1_LIB="$LLVM_BUILD_DIR/lib"
STAGE2_LIB="$LLVM_BUILD_DIR/tools/clang/stage2-bins/lib"
LDFLAGS="-L$STAGE2_LIB/$HOST_TARGET -L$STAGE2_LIB -L$STAGE1_LIB/$HOST_TARGET -L$STAGE1_LIB" \
LD_LIBRARY_PATH="$STAGE2_LIB/$HOST_TARGET:$STAGE2_LIB:$STAGE1_LIB/$HOST_TARGET:$STAGE1_LIB" \
cmake3 --build "$BUILD_DIR" --target install-lldb
popd

ccache -s
