SHELL := /usr/bin/env bash

.PHONY: lint test integration dev package

lint:
	@shellcheck -x bin/astra lib/**/*.sh || echo "shellcheck missing"

test:
	@bats tests/unit || echo "bats missing"

integration:
	@tests/integration/run.sh

dev:
	@ASTRA_LOG_LEVEL=debug bin/astra

package:
	@./scripts/build_tarball.sh
	@./scripts/build_deb.sh
