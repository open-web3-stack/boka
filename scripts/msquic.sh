#!/usr/bin/env bash

set -e


# Setup quic C module
CWD=$(pwd)

mkdir -p .lib

system=$(uname -s)

arch=$(uname -m)



cd Networking/Sources/msquic || { echo "Submodule directory not found"; exit 1; }

rm -rf build

mkdir build && cd build

if [ $system = "Darwin" ]; then
    cmake -DENABLE_LOGGING=OFF  -DCMAKE_OSX_ARCHITECTURES=$arch -DCMAKE_C_FLAGS="-Wno-invalid-unevaluated-string" -DQUIC_BUILD_SHARED=off ..
fi

if [ $system = "Linux" ]; then
    cmake -G 'Unix Makefiles' -DENABLE_LOGGING=OFF  -DCMAKE_OSX_ARCHITECTURES=$arch -DCMAKE_C_FLAGS="-Wno-invalid-unevaluated-string" -DQUIC_BUILD_SHARED=off ..
fi

cmake --build . || { echo "Build msquic library failed"; exit 1; }

cp bin/Release/libmsquic.a ${CWD}/.lib

echo "Setup msquic successfully."
