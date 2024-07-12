#!/usr/bin/env bash

set -e


# Setup bandersnatch vrf c binding
cd "$(dirname "$0")/../Utils/Sources/bandersnatch" || { echo "directory not found"; exit 1; }

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
