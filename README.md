# Boka

Boka / 波卡 / bō kǎ: A JAM implementation built with Swift, brought to you by Laminar Labs.

## Development Environment

- Install tools and deps
  - macos: `brew install swiftlint swiftformat rocksdb openssl`
  - linux: `apt-get install librocksdb-dev libzstd-dev libbz2-dev liblz4-dev libssl-dev`
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

First install the latest [swiftwasm](https://github.com/swiftwasm/swift/releases). There are 2 options for installing, install toolchain (recommended) or install sdk.


**If install toolchain:**

`/Library/Developer/Toolchains/` should contain the installed toolchains. (To uninstall, just delete the toolchain)

```bash
# check swiftwasm toolchain swift version
env TOOLCHAINS=swiftwasm swift --version

# update deps
swift package update --package-path PVMShell

# build wasm
env TOOLCHAINS=swiftwasm swift build --package-path PVMShell --triple wasm32-unknown-wasi --static-swift-stdlib

# output is in `.build/wasm32-unknown-wasi/debug`
```

**If install sdk:**

```bash
# list sdk
swift sdk list

# build with a listed swiftwasm sdk
swift build --package-path PVMShell --swift-sdk 6.0-SNAPSHOT-2024-10-10-a-wasm32-unknown-wasi
```

Done
- [x] fixed swift-numeric `_Float16` not supported problem using a custom fork of swift-numeric
- [x] fixed `no such module 'Foundation'` using [`--static-swift-stdlib`](https://github.com/swiftwasm/swift/issues/5560)
- [x] fixed unsuportted multi-thread func errors by exclude `swift-metrics` and `swift-distributed-tracing`
- [x] fix `LRUCache` unsupported modules by using a custom fork with Notification feature removed
- [x] fix `Utils` multi-thread function usage by excluding with a flag

Todo
- [ ] fix compiler crash in `ConfigLimitedSizeArray.swift:21:12` init
- [ ] avoid static lib by using compilation flag to exclude them or put them in a separate package
