#!/bin/bash -eEux

cd "$(dirname "$0")"

yum install -y cmake3 ninja-build

PATH=$(echo /opt/python/cp39*/bin):$PATH
export PATH

./build-twostage-pure.sh
