#!/bin/bash -eEu

cd "$(dirname "$0")"

yum install -y cmake3 ninja-build

PATH=$(echo /opt/python/cp38*/bin):$PATH
export PATH

./build-stage1-pure.sh
