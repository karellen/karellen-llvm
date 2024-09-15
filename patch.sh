#!/bin/bash

set -eEux
set -o pipefail

for p in patches/*; do
  patch -d llvm-project -p1 < $p
done
