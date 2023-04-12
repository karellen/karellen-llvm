#!/bin/bash -eEux


TARGET_RUNTIME="$(readlink -nf llvm.runtime)"
TARGET_DEBUG="$(readlink -nf llvm.debug)"
TARGET_CLANG="$(readlink -nf llvm.bin)"

BIN_SOURCE="$(readlink -nf llvm.twostage.build/tools/clang/stage2-bins)"
BIN_TARGET="$(readlink -nf llvm.twostage.bin)"

pushd $BIN_TARGET

rm -rf $TARGET_RUNTIME || true
rm -rf $TARGET_DEBUG || true
rm -rf $TARGET_CLANG || true
mkdir -p $TARGET_RUNTIME
mkdir -p $TARGET_DEBUG
mkdir -p $TARGET_CLANG

ninja-build -C $BIN_SOURCE install-cxx install-cxxabi install-unwind
ninja-build -C $BIN_SOURCE install-LLVM install-LTO install-Remarks

find $TARGET_CLANG -name \*.a -delete || true
rm -rf $TARGET_CLANG/include

for f in $(find $TARGET_CLANG -name \*.so\*); do
  if [[ "$(file $f)" =~ ELF.*with\ debug_info ]]; then
      objcopy --only-keep-debug "$f" "$f".debug
      strip -g "$f"
      objcopy --add-gnu-debuglink="$f".debug "$f"
      TARGET_DIR="$(dirname "$f")"
      TARGET_DIR="$TARGET_DEBUG${TARGET_DIR##$TARGET_CLANG}/"
      mkdir -p "$TARGET_DIR"
      mv "$f".debug "$TARGET_DIR"
  fi
done

find $TARGET_DEBUG -type f -exec chmod -x {} \;
cp -r $TARGET_CLANG/* $TARGET_RUNTIME

ninja-build -C $BIN_SOURCE install

for f in $(find $TARGET_CLANG -name \*); do
  if [[ "$(file $f)" =~ ELF.*with\ debug_info ]]; then
      strip -g "$f"
  fi
done

find $TARGET_CLANG/lib -maxdepth 1 -a -name \*.a -delete || true
rm -rf $TARGET_CLANG/include/clang*
rm -rf $TARGET_CLANG/include/lld*

for f in $(find $TARGET_CLANG -type f); do
    F_RUNTIME="$TARGET_RUNTIME${f##$TARGET_CLANG}"
    if [ -e $F_RUNTIME ]; then
      rm $f
    fi
done

for f in $(find $TARGET_CLANG -type l); do
    if [ -L $f -a ! -a $f ]; then
      rm $f
    fi
done



# cp -r ../llvm.bin.lib/* ../llvm.bin
# cp -r ../llvm.bin.debug/* ../llvm.bin/lib
popd

