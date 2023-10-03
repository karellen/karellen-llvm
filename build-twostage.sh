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

rm -rf "$BUILD_DIR/"* || true
rm -rf "$TARGET_DIR/"* || true

PROJECT_VERSION="$(./version_extractor.py -m cmake -d "$SOURCE_DIR")"
PARALLEL_JOBS="$(python -c 'from subprocess import check_output; print(int(max(2, int(check_output(["nproc"], universal_newlines=True))/2 - 2)))')"
cmake3 -G Ninja \
  -Wno-dev \
  $PROJECT_VERSION \
  -DLLVM_CCACHE_BUILD=$LLVM_CCACHE_BUILD \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -DPYTHON_HOME="$(python -c 'import sys; print(sys.exec_prefix)')" \
  -DPYTHON_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -DPython3_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -DLLVM_PARALLEL_COMPILE_JOBS="$PARALLEL_JOBS" \
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

./packager.py -S 2 -b "$BUILD_DIR" -t "$TARGET_DIR" -s "$SOURCE_DIR"
