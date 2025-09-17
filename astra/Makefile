SHELL := /usr/bin/env bash

.PHONY: lint dev package

lint:
	@shellcheck -x bin/astra lib/**/*.sh || echo "shellcheck missing"

dev:
	@ASTRA_LOG_LEVEL=debug bin/astra

package:
	@./scripts/build_tarball.sh
	@./scripts/build_deb.sh
