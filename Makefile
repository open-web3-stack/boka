.PHONY: default
default: build

.git/hooks/pre-commit: .githooks/pre-commit
	cp .githooks/pre-commit .git/hooks/pre-commit

.PHONY: githooks
githooks: .git/hooks/pre-commit

.PHONY: deps
deps: Utils/Sources/blst/lib/libblst.a

Utils/Sources/blst/lib/libblst.a:
	./scripts/deps.sh

.PHONY: test
test: githooks deps
	./scripts/run.sh test

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
	rm Utils/Sources/blst/lib/libblst.a

.PHONY: lint
lint: githooks
	swiftlint lint --config .swiftlint.yml --strict

.PHONY: format
format: githooks
	swiftformat .
