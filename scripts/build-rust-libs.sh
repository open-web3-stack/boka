#!/usr/bin/env bash

set -e

# Setup rust libs c binding
CWD=$(pwd)

mkdir -p .lib

cargo build --release --lib

cd ${CWD}
cp target/release/*.a .lib

echo "Setup rust libs c binding successfully."
