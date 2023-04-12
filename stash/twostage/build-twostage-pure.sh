#!/bin/bash -eEu

SOURCE_DIR="$(readlink -nf ../llvm-project/llvm)"
BUILD_DIR="$(readlink -nf ../llvm.twostage.build)"
TARGET_DIR="$(readlink -nf ../llvm.twostage.bin)"
LLVM_DISTRO_CONF="$(readlink -nf twostage.cmake)"

# pip install --force-reinstall wheel-axle
# python -c pass

rm -rf "$BUILD_DIR/"* || true
rm -rf "$TARGET_DIR/"* || true

cmake3 -G Ninja \
  -Wno-dev \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -DPYTHON_HOME="$(python -c 'import sys; print(sys.exec_prefix)')" \
  -DPYTHON_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -DPython3_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -DLLVM_PARALLEL_COMPILE_JOBS="$(python -c 'from subprocess import check_output; print(int(max(2, int(check_output(["nproc"], universal_newlines=True))/2 - 2)))')" \
  -C "$LLVM_DISTRO_CONF" \
  -S "$SOURCE_DIR" -B "$BUILD_DIR" # \
  # --debug-output --trace --trace-expand --trace-source llvm/runtimes/CMakeLists.txt

cat <<EOF

**************************************************
STAGE 1
**************************************************

EOF

cmake3 --build "$BUILD_DIR" --target clang-bootstrap-deps

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

exit 0

AXLE_DIR="$(mktemp -d)"
DIST_DIR="$(readlink -nf ../wheels)"

cp setup.py "$AXLE_DIR"
pushd "$AXLE_DIR"
./setup.py "$SOURCE_DIR" "$TARGET_DIR" bdist_axle --dist-dir "$DIST_DIR"
popd
