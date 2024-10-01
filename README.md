# Boka

JAM built with Swift

## Development Environment

- Install tools and eps
  - macos: `brwe install swiftlint swiftformat rocksdb`
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
