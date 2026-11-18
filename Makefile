.PHONY: test lint bench bundle demo

# The end-to-end tests run once per agent, against the source tree and the
# one-file build; CI runs one agent per job.
AGENTS ?= opencode claude codex
BUNDLE := .github/release/apathy.zsh
PLUGINS ?= apathy.plugin.zsh $(BUNDLE)
VERSION := $(shell cat .github/release/version.txt)

test: lint
	zsh -f test/classify.test.zsh
	zsh -f test/models.test.zsh
	zsh -f test/update.test.zsh
	for plugin in $(PLUGINS); do \
		APATHY_TEST_PLUGIN="$(CURDIR)/$$plugin" zsh -f test/agents.test.zsh || exit 1; \
		for agent in $(AGENTS); do \
			for t in widget context log; do \
				APATHY_TEST_PLUGIN="$(CURDIR)/$$plugin" APATHY_TEST_AGENT=$$agent zsh -f test/$$t.test.zsh || exit 1; \
			done; \
		done; \
	done
	zsh -f test/bench.zsh

lint:
	zsh -n apathy.plugin.zsh lib/*.zsh test/*.zsh .github/release/*.zsh
	@zsh -f .github/release/bundle.zsh | cmp -s - $(BUNDLE) || { echo '$(BUNDLE) is stale: run make bundle'; exit 1; }
	@for f in apathy.plugin.zsh $(BUNDLE); do \
		zsh -fc 'source $$1; [[ $$APATHY_VERSION == $$2 ]]' _ $$f $(VERSION) || { echo "$$f: version isn't $(VERSION)"; exit 1; }; \
	done
	@grep -q 'message=$(VERSION)"' README.md || { echo "README.md: version badge isn't $(VERSION)"; exit 1; }

bench:
	zsh -f test/bench.zsh

# The one-file build that installs and apathy-update download.
bundle:
	zsh -f .github/release/bundle.zsh > $(BUNDLE)

demo:
	ZDOTDIR="$(CURDIR)/.github/demo" zsh -i
