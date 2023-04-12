#!/bin/bash -eEux

SOURCE_DIR="$(readlink -nf llvm-project/llvm)"
BUILD_DIR="$(readlink -nf llvm.twostage.build)"
TARGET_DIR="$(readlink -nf llvm.twostage.bin)"

./packager.py -b "$BUILD_DIR/tools/clang/stage2-bins" -t "$TARGET_DIR" -s "$SOURCE_DIR"
