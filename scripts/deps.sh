#!/usr/bin/env bash


# Setup blst C module
cd Utils/Sources/blst || { echo "Submodule directory not found"; exit 1; }

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


# Setup bandersnatch vrf c binding
cd ../Bandersnatch || { echo "directory not found"; exit 1; }

mkdir -p include
mkdir -p lib

cargo build --lib

cp target/debug/libbandersnatch_vrfs.a lib

cat <<EOL > include/module.modulemap
module bandersnatch_vrfs {
  header "./bindings.h"
  link "bandersnatch_vrfs"
  export *
}
EOL

echo "Setup bandersnatch_vrfs successfully."
