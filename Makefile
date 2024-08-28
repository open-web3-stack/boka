.PHONY: default
default: build

.git/hooks/pre-commit: .githooks/pre-commit
	cp .githooks/pre-commit .git/hooks/pre-commit

.PHONY: githooks
githooks: .git/hooks/pre-commit

.PHONY: deps
deps: .lib/libblst.a .lib/libbandersnatch_vrfs.a .lib/librocksdb.a .lib/libec.a .lib/libmsquic.a

.lib/libblst.a:
	./scripts/blst.sh

.lib/libbandersnatch_vrfs.a: $(wildcard Utils/Sources/bandersnatch/src/*)
	./scripts/bandersnatch.sh

.lib/libec.a: $(wildcard Utils/Sources/erasure-coding/src/*)
	./scripts/erasure-coding.sh

.lib/librocksdb.a:
	./scripts/rocksdb.sh

.lib/libmsquic.a:
	./scripts/msquic.sh
	
.PHONY: test
test: githooks deps
	./scripts/runTests.sh test

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

.PHONY: run
run: githooks
	swift run --package-path Boka
