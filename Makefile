# Dev convenience only; the tool itself is the single file ./kdrive-tool.
.RECIPEPREFIX = >
SHELL_FILES := kdrive-tool tests/helpers.bash
BATS_FILES := $(wildcard tests/*.bats)

.PHONY: check lint fmt test
check: lint test

lint:
> shellcheck -x $(SHELL_FILES) $(BATS_FILES)
> shfmt -d $(SHELL_FILES)
> shfmt -ln bats -d $(BATS_FILES)

fmt:
> shfmt -w $(SHELL_FILES)
> shfmt -ln bats -w $(BATS_FILES)

test:
> bats tests/
