#!/usr/bin/env bash

set -e

release=v1

os=$(uname -s)
arch=$(uname -m)

if [ "$os" = "Darwin" ]; then
    filename="macos-15-build.tar.gz"
elif [ "$os" = "Linux" ]; then
    filename="ubuntu-latest-build.tar.gz"
fi

cd .lib

curl -L -o "$filename" "https://github.com/AcalaNetwork/boka-external-libs/releases/download/$release/$filename"

tar -xvf "$filename"

rm "$filename"

mv build/$os-$arch/* .
