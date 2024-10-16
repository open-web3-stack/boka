.PHONY: default
default: build

.git/hooks/pre-commit: .githooks/pre-commit
	cp .githooks/pre-commit .git/hooks/pre-commit

.PHONY: githooks
githooks: .git/hooks/pre-commit

.PHONY: deps
deps: .lib/libbls.a .lib/libbandersnatch_vrfs.a .lib/libec.a .lib/libmsquic.a

.lib/libbls.a: $(wildcard Utils/Sources/bls/src/*)
	./scripts/build-rust-libs.sh

.lib/libbandersnatch_vrfs.a: $(wildcard Utils/Sources/bandersnatch/src/*)
	./scripts/build-rust-libs.sh

.lib/libec.a: $(wildcard Utils/Sources/erasure-coding/src/*)
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

.PHONY: format-all
format-all: format format-cargo

.PHONY: run
run: githooks
	swift run --package-path Boka
