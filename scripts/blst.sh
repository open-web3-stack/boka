#!/usr/bin/env bash

set -e


# Setup blst C module
cd "$(dirname "$0")/../Utils/Sources/blst" || { echo "Submodule directory not found"; exit 1; }

./build.sh || { echo "Build blst library failed"; exit 1; }

mkdir -p include
mkdir -p lib

cp libblst.a lib/

cat <<EOL > include/module.modulemap
module blst {
  header "../bindings/blst.h"
  link "blst"
  export *
}
EOL

echo "Setup blst successfully."
