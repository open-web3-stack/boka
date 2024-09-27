#!/usr/bin/env bash

set -e


# Setup bandersnatch vrf c binding
CWD=$(pwd)

mkdir -p .lib

cd Utils/Sources/bandersnatch || { echo "directory not found"; exit 1; }

cargo build --release --lib

cp target/release/libbandersnatch_vrfs.a ${CWD}/.lib

echo "Setup bandersnatch successfully."
