.PHONY: default
default: build

.git/hooks/pre-commit: .githooks/pre-commit
	cp .githooks/pre-commit .git/hooks/pre-commit

.PHONY: githooks
githooks: .git/hooks/pre-commit

.PHONY: deps
deps: .lib/libbls.a .lib/libbandersnatch_vrfs.a .lib/libec.a .lib/libed25519_zebra_ffi.a .lib/libmsquic.a

.lib/libbls.a: $(wildcard Utils/Sources/bls/src/*)
	./scripts/build-rust-libs.sh

.lib/libbandersnatch_vrfs.a: $(wildcard Utils/Sources/bandersnatch/src/*)
	./scripts/build-rust-libs.sh

.lib/libec.a: $(wildcard Utils/Sources/erasure-coding/src/*)
	./scripts/build-rust-libs.sh

.lib/libed25519_zebra_ffi.a: $(wildcard Utils/Sources/ed25519-zebra/src/*)
	./scripts/build-rust-libs.sh

.lib/libmsquic.a:
	./scripts/external-libs.sh

.PHONY: test
test: githooks deps
	./scripts/runTests.sh test

.PHONY: test-cargo
test-cargo:
	cargo test --manifest-path Utils/Sources/bandersnatch/Cargo.toml

.PHONY: test-all
test-all: test test-cargo

.PHONY: test-coverage
test-coverage:
	./scripts/runTests.sh test --enable-code-coverage

.PHONY: build
build: githooks deps
	./scripts/run.sh build

.PHONY: build-verbose
build-verbose: githooks
	./scripts/run.sh build --verbose

.PHONY: resolve
resolve: githooks
	./scripts/run.sh package resolve

.PHONY: clean
clean:
	./scripts/run.sh package clean

.PHONY: clean-lib
clean-lib:
	rm -f .lib/*.a

.PHONY: clean-all
clean-all: clean clean-lib

.PHONY: lint
lint: githooks
	swiftlint lint --config .swiftlint.yml --strict

.PHONY: format
format: githooks
	swiftformat .

.PHONY: format-cargo
format-cargo:
	cargo fmt --all

.PHONY: format-all
format-all: format format-cargo

.PHONY: format-clang
format-clang:
	find . \( -name "*.c" -o -name "helpers.h" \) -exec clang-format -i {} +

.PHONY: run
run: githooks
	SWIFT_BACKTRACE=enable=yes swift run --package-path Boka Boka --validator

.PHONY: devnet
devnet:
	./scripts/devnet.sh

# Determine build directory using SwiftPM
# This works cross-platform (Linux, macOS) for both x86_64 and arm64
BUILD_DIR := $(shell swift build --show-bin-path -c release 2>/dev/null)
SANDBOX_PATH := $(BUILD_DIR)/boka-sandbox

# Benchmark targets
# Build sandbox in release mode and use it for benchmarks
.PHONY: benchmark
benchmark: githooks deps build-sandbox-release
	cd JAMTests && BOKA_SANDBOX_PATH=$(SANDBOX_PATH) swift package benchmark

.PHONY: benchmark-list
benchmark-list: githooks deps build-sandbox-release
	cd JAMTests && BOKA_SANDBOX_PATH=$(SANDBOX_PATH) swift package benchmark list

.PHONY: benchmark-filter
benchmark-filter: githooks deps build-sandbox-release
	@echo "Usage: make benchmark-filter FILTER=<pattern>"
	@echo "Example: make benchmark-filter FILTER=trie"
	@if [ -z "$(FILTER)" ]; then \
		echo "Error: FILTER parameter is required"; \
		exit 1; \
	fi
	cd JAMTests && BOKA_SANDBOX_PATH=$(SANDBOX_PATH) swift package benchmark --filter $(FILTER)

.PHONY: benchmark-baseline
benchmark-baseline: githooks deps build-sandbox-release
	@echo "Usage: make benchmark-baseline BASELINE=<name>"
	@echo "Example: make benchmark-baseline BASELINE=master"
	@if [ -z "$(BASELINE)" ]; then \
		echo "Error: BASELINE parameter is required"; \
		exit 1; \
	fi
	cd JAMTests && BOKA_SANDBOX_PATH=$(SANDBOX_PATH) swift package --allow-writing-to-directory .benchmarkBaselines/ benchmark baseline update $(BASELINE)

.PHONY: benchmark-compare
benchmark-compare: githooks deps build-sandbox-release
	@echo "Usage: make benchmark-compare BASELINE1=<name1> BASELINE2=<name2>"
	@echo "Example: make benchmark-compare BASELINE1=master BASELINE2=pull_request"
	@if [ -z "$(BASELINE1)" ] || [ -z "$(BASELINE2)" ]; then \
		echo "Error: BASELINE1 and BASELINE2 parameters are required"; \
		exit 1; \
	fi
	cd JAMTests && BOKA_SANDBOX_PATH=$(SANDBOX_PATH) swift package benchmark baseline compare $(BASELINE1) $(BASELINE2)

.PHONY: benchmark-check
benchmark-check: githooks deps build-sandbox-release
	@echo "Usage: make benchmark-check BASELINE1=<name1> BASELINE2=<name2>"
	@echo "Example: make benchmark-check BASELINE1=master BASELINE2=pull_request"
	@if [ -z "$(BASELINE1)" ] || [ -z "$(BASELINE2)" ]; then \
		echo "Error: BASELINE1 and BASELINE2 parameters are required"; \
		exit 1; \
	fi
	cd JAMTests && BOKA_SANDBOX_PATH=$(SANDBOX_PATH) swift package benchmark baseline check $(BASELINE1) $(BASELINE2) --thresholds .benchmarkBaselines/thresholds.json

.PHONY: benchmark-all
benchmark-all: githooks deps build-sandbox-release
	cd JAMTests && BOKA_SANDBOX_PATH=$(SANDBOX_PATH) swift package --allow-writing-to-directory .benchmarkBaselines/ benchmark baseline update all

# Helper target to build sandbox in release mode
.PHONY: build-sandbox-release
build-sandbox-release:
	@echo "Building boka-sandbox in release mode..."
	cd PolkaVM && swift build -c release --product boka-sandbox
