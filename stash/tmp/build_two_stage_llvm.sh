#/bin/bash -eEu

SOURCE_DIR="$(readlink -nf llvm-project/llvm)"
BUILD_DIR="$(readlink -nf llvm.build)"
TARGET_DIR="$(readlink -nf llvm.bin)"
LLVM_DISTRO_CONF="$(readlink -nf Distribution.cmake)"

rm -rf "$BUILD_DIR" || true
rm -rf "$TARGER_DIR" || true

mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR"

cmake -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$TARGET_DIR" \
  -C "$LLVM_DISTRO_CONF" \
  "$SOURCE_DIR"

ninja stage2-distribution

popd
#rm -rf "$BUILD_DIR" || true
