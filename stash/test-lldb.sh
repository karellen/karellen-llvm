#!/bin/bash

set -eEux
set -o pipefail

CCACHE_DIR="$(readlink -nf ccache)"
SOURCE_DIR="$(readlink -nf llvm-project/llvm)"
BUILD_DIR="$(readlink -nf llvm.twostage.build)"
TARGET_DIR="$(readlink -nf llvm.twostage.bin)"
LLVM_DISTRO_CONF="$(readlink -nf twostage.cmake)"

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
PARALLEL_COMPILE_JOBS="$(python -c 'from subprocess import check_output; print(max(2, int(int(check_output(["nproc"], universal_newlines=True))/2 - 2)))')"
PARALLEL_LINK_JOBS="$(python -c 'from subprocess import check_output; print(max(1, int(int(check_output(["nproc"], universal_newlines=True))/8)))')"

OLD_PATH=$PATH
for python_ver in "3.11.8" "3.12.6"; do

PATH=$HOME/.pyenv/versions/$python_ver/bin:$OLD_PATH
export PATH

rm -rf "$BUILD_DIR/"* || true
rm -rf "$TARGET_DIR/"* || true

cmake3 -G Ninja \
  -Wno-dev \
  $PROJECT_VERSION \
  -DLLVM_CCACHE_BUILD=$LLVM_CCACHE_BUILD \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -DPYTHON_HOME="$(python3 -c 'import sys; print(sys.exec_prefix)')" \
  -DPYTHON_EXECUTABLE="$(python3 -c 'import sys; print(sys.executable)')" \
  -DPython3_EXECUTABLE="$(python3 -c 'import sys; print(sys.executable)')" \
  -DLLVM_PARALLEL_COMPILE_JOBS="$PARALLEL_COMPILE_JOBS" \
  -DLLVM_PARALLEL_LINK_JOBS="$PARALLEL_LINK_JOBS" \
  -C "$LLVM_DISTRO_CONF" \
  -S "$SOURCE_DIR" -B "$BUILD_DIR"
cmake3 --build "$BUILD_DIR" --target clang-bootstrap-deps

HOST_TARGET=$("$BUILD_DIR"/bin/llvm-config --host-target)
STAGE1_LIB="$BUILD_DIR/lib"
STAGE2_LIB="$BUILD_DIR/tools/clang/stage2-bins/lib"
LDFLAGS="-L$STAGE2_LIB/$HOST_TARGET -L$STAGE2_LIB -L$STAGE1_LIB/$HOST_TARGET -L$STAGE1_LIB" \
LD_LIBRARY_PATH="$STAGE2_LIB/$HOST_TARGET:$STAGE2_LIB:$STAGE1_LIB/$HOST_TARGET:$STAGE1_LIB" \
cmake3 --build "$BUILD_DIR" --target stage2

LDFLAGS="-L$STAGE2_LIB/$HOST_TARGET -L$STAGE2_LIB -L$STAGE1_LIB/$HOST_TARGET -L$STAGE1_LIB" \
LD_LIBRARY_PATH="$STAGE2_LIB/$HOST_TARGET:$STAGE2_LIB:$STAGE1_LIB/$HOST_TARGET:$STAGE1_LIB" \
./packager.py -S 2 -b "$BUILD_DIR" -t "$TARGET_DIR" -s "$SOURCE_DIR" --project lldb --restore-record

done