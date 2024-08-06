#!/usr/bin/env bash

set -e


# Setup erasure-coding c binding
CWD=$(pwd)

mkdir -p .lib

cd Utils/Sources/erasure-coding || { echo "directory not found"; exit 1; }

cargo build --release --lib

cp target/release/libec.a ${CWD}/.lib

echo "Setup erasure-coding successfully."
