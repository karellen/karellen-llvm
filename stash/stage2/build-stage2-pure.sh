#!/bin/bash -eEu

SOURCE_DIR="$(readlink -nf ../llvm-project/llvm)"
BUILD_DIR="$(readlink -nf ../llvm.stage2.build)"
TARGET_DIR="$(readlink -nf ../llvm.stage2.bin)"
LLVM_DISTRO_CONF="$(readlink -nf stage2.cmake)"

pip install --force-reinstall wheel-axle ../wheels/*stage1*.whl
python -c pass

rm -rf "$BUILD_DIR/"* || true
rm -rf "$TARGET_DIR/"* || true

cmake3 -G Ninja \
  -Wno-dev \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -DPYTHON_HOME="$(python -c 'import sys; print(sys.exec_prefix)')" \
  -DPYTHON_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -DPython3_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -C "$LLVM_DISTRO_CONF" \
  -S "$SOURCE_DIR" -B "$BUILD_DIR"

#  -DLLVM_TABLEGEN="$(which llvm-tblgen)"\

pushd "$BUILD_DIR"

ninja-build install-runtimes

popd

AXLE_DIR="$(mktemp -d)"
DIST_DIR="$(readlink -nf ../wheels)"

cp setup.py "$AXLE_DIR"
pushd "$AXLE_DIR"
./setup.py "$SOURCE_DIR" "$TARGET_DIR" bdist_axle --dist-dir "$DIST_DIR"
popd
