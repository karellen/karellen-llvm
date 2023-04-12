#!/bin/bash -eEu

SOURCE_DIR="$(readlink -nf llvm-project/llvm)"
BUILD_DIR="$(readlink -nf llvm.stage2.build)"
TARGET_DIR="$(readlink -nf llvm.bin)"
LLVM_DISTRO_CONF="$(readlink -nf stage2.cmake)"

rm -rf "$BUILD_DIR/"* || true
rm -rf "$TARGET_DIR/"* || true

export PATH="$(readlink -nf llvm.stage1.bin/bin):$PATH"

mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR"

cmake3 -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DPYTHON_HOME="$(python -c 'import sys; print(sys.exec_prefix)')" \
  -DPYTHON_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -DPython3_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -C "$LLVM_DISTRO_CONF" \
  "$SOURCE_DIR"

popd
