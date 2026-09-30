# Boka

Boka / 波卡 / bō kǎ: A JAM implementation built with Swift, brought to you by Laminar Labs.

## Development Environment

Install tools and dependencies:

**macOS**
```bash
brew install swiftlint swiftformat rocksdb openssl jemalloc zstd
```

**Linux**
```bash
apt-get install librocksdb-dev libzstd-dev libbz2-dev liblz4-dev libssl-dev libjemalloc-dev
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

The Boka CLI supports the following options:

- `-b <path>` / `--base-path <path>`: Directory for the database and keys. Without it, both are in memory.
- `--chain <chain>`: Preset (`minimal`, `dev`, `tiny`, `mainnet`) or path to a chain spec file. Default: `minimal`.
- `--rpc <address>`: Listen address for RPC server. Pass `no` to disable. Default: `127.0.0.1:9955`.
- `--p2p <address>`: Listen address for P2P protocol. Default: `127.0.0.1:0`.
- `--peers <address>`: Add a P2P peer. Repeat `--peers` to add more.
- `--validator`: Run as a validator.
- `--dev-seed <seed>`: For development only. Seed for validator keys.
- `--name <name>`: Node name. For telemetry only.
- `--local`: Enable local mode, whereas peers are not expected.
- `--dev`: Enable dev mode. This is equivalent to `--local --validator`.

Subcommands:

- `generate <output>`: Create a chainspec file at the required output path.
  - `--config <preset>`: `minimal` (default), `dev`, `tiny`, or `mainnet`.
  - `--chainspec <path>`: Use an existing chainspec instead of a preset.
  - `--id <id>`: Override the chain ID.
- `fuzz target`: Wait for JAM conformance fuzzer connections.
  - `--socket-path <path>`: Unix socket path (default: `/tmp/jam_conformance.sock`).
  - `--config <tiny|full>`: Protocol configuration (default: `tiny`).
- `fuzz fuzzer`: Connect to a target and run the JAM conformance fuzzer.
  - `--socket-path <path>`: Unix socket path (default: `/tmp/jam_conformance.sock`).
  - `--config <tiny|full>`: Protocol configuration (default: `tiny`).
  - `--seed <number>`: Random seed (random by default).
  - `--blocks <count>`: Number of blocks to process (default: `200`).
  - `--traces-dir <path>`: Directory containing trace test vectors.

## Testing

- Run all Swift tests: `make test`
- Run specific package: `cd <package> && swift test`
- Run specific package from the repository root: `swift test --package-path <package>`
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

# Forward package-benchmark options to the underlying command
make benchmark BENCHMARK_ARGS="--skip 'pool\\..*' --no-progress"

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

- **PR Benchmarks**: Compare PR changes against master branch and report configured threshold deviations
- **Master Baselines**: Track performance on `master`, stored as artifacts for 90 days

Regression thresholds are configured alongside the benchmark code in
`JAMTests/Benchmarks/Benchmarks/BenchmarkSupport.swift`.

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
- TracingUtils
  - Logging and tracing utilities.
- JAMTests
  - JAM test vectors and benchmarks.
- Fuzzing
  - JAM conformance fuzzing tools.
- Tools
  - Developer utilities for PVM, RPC, and proof-of-concept workflows.
