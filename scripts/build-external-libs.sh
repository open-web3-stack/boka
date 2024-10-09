#!/usr/bin/env bash

set -e

release=v7

mkdir -p .lib
cd .lib

# check if the external libs are already cloned
if [ ! -d "boka-external-libs" ]; then
    git clone https://github.com/open-web3-stack/boka-external-libs --recurse-submodules --shallow-submodules
fi
cd boka-external-libs
git fetch
git checkout $release
./scripts/msquic.sh

system=$(uname -s)
arch=$(uname -m)

mv build/$system-$arch/* ..
