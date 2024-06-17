.PHONY: githooks
githooks:
	cp .githooks/pre-commit .git/hooks/pre-commit

test: githooks
	./scripts/run.sh test
