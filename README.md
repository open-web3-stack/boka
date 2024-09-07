# Boka

JAM built with Swift

## Development Environment

- SwiftLint: `brew install swiftlint`
- SwiftFormat: `brew install swiftformat`
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

## Compile PVM to Wasm

Go to [swiftwasm book](https://book.swiftwasm.org/getting-started/setup.html) and install the latest swiftwasm toolchain. Note that using `--swift-sdk` with a swiftwasm sdk does not work due to some dependencies build issues.

```bash
# build without switch toolchains
cd PVMShell
/Library/Developer/Toolchains/swift-wasm-DEVELOPMENT-SNAPSHOT-2024-09-06-a.xctoolchain/usr/bin/swift build
```
