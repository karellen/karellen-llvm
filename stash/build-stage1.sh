#!/bin/bash -eEu

mkdir -p llvm.stage1.bin
mkdir -p llvm.stage1.build
mkdir -p wheels

docker run --rm -it -e PLAT=manylinux2014_x86_64 \
       -v $(readlink -nf stage1):/io/scripts:ro \
       -v $(readlink -nf llvm-project):/io/llvm-project:ro \
       -v $(readlink -nf llvm.stage1.bin):/io/llvm.stage1.bin \
       -v $(readlink -nf llvm.stage1.build):/io/llvm.stage1.build \
       -v $(readlink -nf wheels):/io/wheels \
       quay.io/pypa/manylinux2014_x86_64 /io/scripts/build-stage1-manylinux.sh
