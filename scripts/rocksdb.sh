#!/usr/bin/env bash

set -e


# Setup rocksdb
CWD=$(pwd)

mkdir -p .lib

cd Database/Sources/rocksdb || { echo "directory not found"; exit 1; }

make static_lib

cp librocksdb.a ${CWD}/.lib

echo "Setup rocksdb successfully."
