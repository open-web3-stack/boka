#!/usr/bin/env bash


# Setup blst C module
CWD=$(pwd)

mkdir -p .lib

cd Utils/Sources/blst || { echo "Submodule directory not found"; exit 1; }

./build.sh || { echo "Build blst library failed"; exit 1; }

cp libblst.a ${CWD}/.lib

echo "Setup blst successfully."
