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

- Run all Swift tests: `make test`
- Run specific package: `cd <package> && swift test`
- Run with filter: `cd <package> && swift test --filter <test-name>`
- Verbose output: `swift test --verbose`
- Run Rust tests: `make test-cargo`
- Run tests with coverage: `make test-coverage`

## Benchmarking

Boka includes comprehensive performance benchmarks covering core blockchain operations:

### Run Benchmarks

```bash
# Run all benchmarks
make benchmark

# List all available benchmarks
make benchmark-list

# Run specific benchmarks by filter pattern
make benchmark-filter FILTER=trie
make benchmark-filter FILTER=runtime
make benchmark-filter FILTER=rocksdb

# Common filter patterns:
# - trie: Merkle trie operations
# - runtime: Runtime state transition functions
# - blockchain: Block import and chain management
# - rocksdb: Persistent storage operations
# - state: State backend operations
# - polkavm: PVM contract execution
# - validator: Validator operations
# - w3f: Test vector processing
```

### Benchmark Baselines

Baselines are used to track performance over time and detect regressions:

```bash
# Create/update a baseline
make benchmark-baseline BASELINE=master
make benchmark-baseline BASELINE=pull_request

# Compare two baselines
make benchmark-compare BASELINE1=master BASELINE2=pull_request

# Check for performance regressions against thresholds
make benchmark-check BASELINE1=master BASELINE2=pull_request
```

### CI/CD Integration

Benchmarks run automatically in CI:

- **PR Benchmarks**: Compare PR changes against master branch, fail on regressions
- **Nightly Benchmarks**: Track performance over time, stored as artifacts for 90 days

Regression thresholds are configured in `JAMTests/.benchmarkBaselines/thresholds.json`.

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
