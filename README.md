# Boka

JAM built with Swift

## Development Environment

- Install tools and eps
  - macos: `brew install swiftlint swiftformat rocksdb`
  - linux: `apt-get install librocksdb-dev libzstd-dev libbz2-dev liblz4-dev`
- Precommit hooks: `make githooks`
- Pull submodules: `git submodule update --init --recursive`
- Setup deps: `make deps`

## Packages

- Boka
  - The CLI entrypoint. Handles CLI arg parsing and launch `Node` with corresponding config.
- Node
  - The API for the blockchain node. Provide API to create various components and assemble the blockchain node.
- Blockchain
  - Implements the data structure, state transform function and consensus. Used by `Node`.
- RPC
  - Provide the RPC interface for the blockchain node. Uses `Blockchain` and used by `Boka`.
- Database
  - Provide the database interface for the blockchain node. Used by `Node`.
- Networking
  - Provide the networking interface for the blockchain node. Used by `Node`.
- Utils
  - Provide the common utilities for the blockchain node.
- TracingUtils
  - Provide the tracing utilities.
- Codec
  - Implements JAM Codec.
- PolkaVM
  - Implements the Polka Virtual Machine.
- PVMShell
  - A module that can be compiled to Wasm for use in [debugger](https://pvm.fluffylabs.dev/).
- JAMTests
  - Integrate the JAM test vectors.

## Compile PVM to Wasm

Go to [swiftwasm book](https://book.swiftwasm.org/getting-started/setup.html) for docs.

First install the latest [swiftwasm](https://github.com/swiftwasm/swift/releases). There are 2 options for installing, *install as toolchain* or *install as sdk*.


**If install as toolchain:**

`/Library/Developer/Toolchains/` should contain the installed toolchains. (To uninstall, just delete the toolchain)

```bash
# check swiftwasm toolchain version
env TOOLCHAINS=swiftwasm swift --version

# build wasm
env TOOLCHAINS=swiftwasm swift build --package-path PVMShell --triple wasm32-unknown-wasi

# output is in `.build/wasm32-unknown-wasi/debug`
```

**If install as sdk:**

```bash
# list sdk
swift sdk list

swift build --package-path PVMShell --swift-sdk 6.0-SNAPSHOT-2024-10-10-a-wasm32-unknown-wasi
```

Both have same error now:
- `_Float16 is not supported on this target` (from swift-numerics)
