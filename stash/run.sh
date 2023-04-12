#!/bin/bash -eEu

rm -rf build dist *.egg-info include
./setup.py bdist_wheel -k
