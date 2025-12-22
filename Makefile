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
	cargo fmt --manifest-path Utils/Sources/bandersnatch/Cargo.toml
	cargo fmt --manifest-path Utils/Sources/erasure-coding/Cargo.toml

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
