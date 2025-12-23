# Boka

Boka / 波卡 / bō kǎ: A JAM implementation built with Swift, brought to you by Laminar Labs.

## Development Environment

Install tools and dependencies:

**macOS**
```bash
brew install swiftlint swiftformat rocksdb openssl
```

**Linux**
```bash
apt-get install librocksdb-dev libzstd-dev libbz2-dev liblz4-dev libssl-dev
```

Setup the project:

```bash
# Install precommit hooks
make githooks

# Pull submodules
git submodule update --init --recursive

# Setup dependencies
make deps
```

## Run

- Run the node: `make run`
- Run a devnet: `make devnet`

## CLI Usage

The Boka CLI supports the following arguments:

- `--base-path <path>`: Base path to database files.
- `--chain <chain>`: A preset config or path to chain config file. Default: `minimal`.
- `--rpc <address>`: Listen address for RPC server. Pass 'no' to disable. Default: `127.0.0.1:9955`.
- `--p2p <address>`: Listen address for P2P protocol. Default: `127.0.0.1:0`.
- `--peers <address>`: Specify peer P2P addresses.
- `--validator`: Run as a validator.
- `--operator-rpc <address>`: Listen address for operator RPC server. Pass 'false' to disable.
- `--dev-seed <seed>`: For development only. Seed for validator keys.
- `--name <name>`: Node name. For telemetry only.
- `--local`: Enable local mode, whereas peers are not expected.
- `--dev`: Enable dev mode. This is equivalent to `--local --validator`.

## Testing

- Run Swift tests: `make test`
- Run Rust tests: `make test-cargo`
- Run tests with coverage: `make test-coverage`

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
- PolkaVM
  - The PVM implementation.
- Codec
  - The JAM codec implementation.
- Utils
  - Provide the common utilities for the blockchain node.
