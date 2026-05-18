.PHONY: help test lint perf check check-all install uninstall clean release-check dist

PREFIX ?= $(HOME)/.local
VERSION := $(shell cat VERSION)

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: ## Run the end-to-end test suite
	@bash tests/e2e.sh

lint: ## Run shellcheck on all shell scripts
	@shellcheck -s bash \
	    bin/cliwrap \
	    lib/*.sh \
	    install.sh \
	    tests/*.sh \
	    examples/*/*.sh

perf: ## Run performance regression test
	@bash tests/perf.sh

check: lint test ## Run lint + test

check-all: lint test perf ## Run lint + test + perf

install: ## Install to $(PREFIX) (default: ~/.local)
	@PREFIX=$(PREFIX) bash install.sh

uninstall: ## Remove installed files
	@rm -rf "$(PREFIX)/share/cliwrap" "$(PREFIX)/bin/cliwrap"
	@echo "Removed cliwrap from $(PREFIX)"

dist: ## Build release tarball in dist/
	@mkdir -p dist
	@tar --exclude=dist --exclude=.git --exclude=.github \
	     -czf dist/cliwrap-$(VERSION).tar.gz \
	     --transform 's,^,cliwrap-$(VERSION)/,' \
	     VERSION LICENSE README.md install.sh \
	     bin lib examples
	@echo "Built dist/cliwrap-$(VERSION).tar.gz"

release-check: ## Verify everything is ready for a release
	@echo "Version:     $(VERSION)"
	@git diff --quiet || { echo "ERROR: working tree dirty"; exit 1; }
	@grep -q "## \[$(VERSION)\]" CHANGELOG.md || { echo "ERROR: CHANGELOG has no entry for $(VERSION)"; exit 1; }
	@$(MAKE) check-all
	@echo "✓ Ready to release $(VERSION)"
	@echo "Run: git tag v$(VERSION) && git push --tags"

clean: ## Remove build artifacts
	@rm -rf dist/
	@find . -name "*.bak" -delete
