.git/hooks/pre-commit: .githooks/pre-commit
	cp .githooks/pre-commit .git/hooks/pre-commit

.PHONY: githooks
githooks: .git/hooks/pre-commit

.PHONY: deps
deps: githooks
	./scripts/deps.sh

.PHONY: test
test: githooks deps
	./scripts/run.sh test

.PHONY: build
build: githooks deps
	./scripts/run.sh build

.PHONY: clean
clean:
	./scripts/run.sh package clean

.PHONY: lint
lint: githooks
	swiftlint lint --config .swiftlint.yml --strict

.PHONY: format
format: githooks
	swiftformat .
