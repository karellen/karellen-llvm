#/bin/bash -eEu

LLVM_SRC="$(readlink -nf llvm-project/compiler-rt)"
LLVM_BIN="$(readlink -nf llvm.bin.scratch)"

INSTALL_DIR="$(readlink -nf compiler-rt)"
BUILD_DIR="$(readlink -nf /tmp/llvm.build)"

rm -rf "$BUILD_DIR" || true
rm -rf "$INSTALL_DIR" || true

mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR"

export PATH=$LLVM_BIN/bin:$PATH

cmake -G Ninja \
  -DLLVM_CONFIG_PATH="$LLVM_BIN/bin/llvm-config" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DLIBCXX_USE_COMPILER_RT=YES \
  -DLIBCXXABI_USE_COMPILER_RT=YES \
  -DLLVM_ENABLE_DUMP=ON \
  -DLLVM_BUILD_LLVM_DYLIB=ON \
  -DLLVM_LINK_LLVM_DYLIB=ON \
  -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON -DLLVM_INSTALL_CCTOOLS_SYMLINKS=ON \
  -DLLVM_PARALLEL_COMPILE_JOBS=8 -DLLVM_PARALLEL_LINK_JOBS=8 \
  "$LLVM_SRC"

cmake --build . --target install
popd
rm -rf "$BUILD_DIR" || true
