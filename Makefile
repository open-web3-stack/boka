.git/hooks/pre-commit: .githooks/pre-commit
	cp .githooks/pre-commit .git/hooks/pre-commit

.PHONY: githooks
githooks: .git/hooks/pre-commit

.PHONY: test
test: githooks
	./scripts/run.sh test

.PHONY: build
build: githooks
	./scripts/run.sh build

.PHONY: lint
lint: githooks
	swiftlint lint --config .swiftlint.yml --strict

.PHONY: format
format: githooks
	swiftformat .
