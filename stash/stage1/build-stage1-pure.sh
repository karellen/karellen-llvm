#!/bin/bash -eEu

SOURCE_DIR="$(readlink -nf ../llvm-project/llvm)"
BUILD_DIR="$(readlink -nf ../llvm.stage1.build)"
TARGET_DIR="$(readlink -nf ../llvm.stage1.bin)"
LLVM_DISTRO_CONF="$(readlink -nf stage1.cmake)"

pip install wheel-axle
pip uninstall -y karellen-llvm-stage1

rm -rf "$BUILD_DIR/"* || true
rm -rf "$TARGET_DIR/"* || true

# set -x

cmake3 -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -DPYTHON_HOME="$(python -c 'import sys; print(sys.exec_prefix)')" \
  -DPYTHON_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -DPython3_EXECUTABLE="$(python -c 'import sys; print(sys.executable)')" \
  -C "$LLVM_DISTRO_CONF" \
  -S "$SOURCE_DIR" -B "$BUILD_DIR"

pushd "$BUILD_DIR"

ninja-build install

popd

for f in $(find $TARGET_DIR ); do
  if [[ "$(file $f)" =~ ELF.* ]]; then
      strip -s "$f"
  fi
done

AXLE_DIR="$(mktemp -d)"
DIST_DIR="$(readlink -nf ../wheels)"

cp setup.py "$AXLE_DIR"
pushd "$AXLE_DIR"
./setup.py "$SOURCE_DIR" "$TARGET_DIR" bdist_axle --dist-dir "$DIST_DIR"
popd
