#!/bin/bash -eEux

cd "$(dirname "$0")"

yum install -y cmake3 ninja-build

PATH=$(echo /opt/python/cp38*/bin):$PATH
export PATH

./build-stage2-pure.sh
