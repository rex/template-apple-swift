# make/ci.mk — every gate that runs WITHOUT Xcode.
#
# `make ci-linux` is the whole contract with the CI workflow: .github/workflows
# /ci.yml's gates job runs this and nothing else, so CI can never drift into a
# reimplementation of the repo's own rules (ADR-0003). It is also the honest
# answer on a Linux box: run it, then say plainly that the compile gates did
# not run.
#
# It runs EVERY step even after one fails, then reports a summary — one run
# tells you everything that is wrong, instead of one thing at a time.
#
# Fail-closed vs skip: the Python gates (architecture, docs, version, YAML,
# structure, secrets) fail closed — a gate that cannot run is a failure. Steps
# that depend on an optional external tool (shellcheck, ruby, yamllint,
# check-jsonschema) or on a component the generator may have removed
# (template/, the spinner corpus) skip loudly and say why.

.PHONY: ci-linux ci-yaml ci-structure ci-pytest ci-vibe ci-shell ci-ruby ci-yamllint

# Every YAML the build reads. A parse error here breaks `xcodegen generate` or
# the generator, and both failures are much louder later than they need to be.
CI_YAML_GLOBS := project.yml xcodegen/components/*.yml \
                 template/components.yaml template/ci-combos/*.yaml \
                 .github/workflows/*.yml .pre-commit-config.yaml VIBE.yaml

## ci-linux: Run every non-Xcode gate, continue past failures, summarize
ci-linux:
	@echo ""
	@echo "$(BOLD)$(CYAN)ci-linux — every gate that runs without Xcode$(RESET)"
	@echo "$(CYAN)Compile truth is macOS-only: this does NOT build or test the app.$(RESET)"
	@fails=0; \
	run() { \
		label="$$1"; shift; \
		echo ""; \
		echo "$(BOLD)── $$label ──$(RESET)"; \
		if "$$@"; then :; else \
			echo "$(RED)   ✗ $$label FAILED$(RESET)"; \
			fails=$$((fails+1)); \
		fi; \
	}; \
	run "architecture"     $(MAKE) --no-print-directory check-architecture; \
	run "required docs"    $(MAKE) --no-print-directory check-docs; \
	run "version bumped"   $(MAKE) --no-print-directory check-version-bumped; \
	run "markdown links"   $(MAKE) --no-print-directory check-links; \
	run "yaml parses"      $(MAKE) --no-print-directory ci-yaml; \
	run "template structure" $(MAKE) --no-print-directory ci-structure; \
	run "generator tests"  $(MAKE) --no-print-directory ci-pytest; \
	run "spinner corpus"   $(MAKE) --no-print-directory spinner-check; \
	run "VIBE.yaml schema" $(MAKE) --no-print-directory ci-vibe; \
	run "shellcheck"       $(MAKE) --no-print-directory ci-shell; \
	run "ruby syntax"      $(MAKE) --no-print-directory ci-ruby; \
	run "yamllint"         $(MAKE) --no-print-directory ci-yamllint; \
	run "apple secret scan" ./scripts/apple/scan-plist-secrets.sh; \
	run "no serena"        $(MAKE) --no-print-directory check-no-serena; \
	echo ""; \
	if [ "$$fails" -gt 0 ]; then \
		echo "$(RED)$(BOLD)ci-linux: $$fails gate(s) failed.$(RESET)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)$(BOLD)ci-linux: all gates passed (compile gates NOT run — macOS only).$(RESET)"

## ci-yaml: Every YAML the build depends on parses (fails closed)
ci-yaml:
	@if python3 -c 'import yaml' 2>/dev/null; then PY="python3"; \
	elif command -v uv >/dev/null 2>&1; then PY="uv run --quiet --with pyyaml python3"; \
	else \
		echo "$(RED)The YAML gate needs PyYAML: install uv, or pip install pyyaml.$(RESET)"; \
		exit 1; \
	fi; \
	load='import sys,yaml; yaml.safe_load(open(sys.argv[1]))'; \
	bad=0; \
	for f in $(CI_YAML_GLOBS); do \
		[ -f "$$f" ] || continue; \
		if $$PY -c "$$load" "$$f" >/dev/null 2>&1; then \
			echo "  ok   $$f"; \
		else \
			echo "$(RED)  FAIL $$f$(RESET)"; \
			$$PY -c "$$load" "$$f" 2>&1 | tail -3 | sed 's/^/       /'; \
			bad=$$((bad+1)); \
		fi; \
	done; \
	[ "$$bad" -eq 0 ] || { echo "$(RED)$$bad YAML file(s) do not parse.$(RESET)"; exit 1; }

## ci-structure: The template's own structural gate (template/verify.py)
ci-structure:
	@if [ ! -f template/verify.py ]; then \
		echo "$(YELLOW)template/ is gone — this repo was generated; nothing to verify.$(RESET)"; \
		exit 0; \
	fi; \
	if command -v uv >/dev/null 2>&1; then \
		uv run template/verify.py --root .; \
	else \
		python3 template/verify.py --root .; \
	fi

## ci-pytest: The generator's own test suite (template repo only)
ci-pytest:
	@if [ ! -d template/tests ]; then \
		echo "$(YELLOW)template/tests absent — this repo was generated; nothing to run.$(RESET)"; \
		exit 0; \
	fi; \
	if ! command -v uv >/dev/null 2>&1; then \
		echo "$(YELLOW)uv not installed — generator tests skipped (install: https://docs.astral.sh/uv/).$(RESET)"; \
		exit 0; \
	fi; \
	uv run --with pytest,pyyaml -m pytest template/tests -q

## ci-vibe: VIBE.yaml validates against the merged skeleton + skill schema
ci-vibe:
	@if [ ! -f scripts/validate_vibe_yaml.py ]; then \
		echo "$(YELLOW)scripts/validate_vibe_yaml.py absent — run 'make sync-skeleton'. Skipped.$(RESET)"; \
		exit 0; \
	fi; \
	if ! command -v check-jsonschema >/dev/null 2>&1; then \
		echo "$(YELLOW)check-jsonschema not installed — schema check skipped.$(RESET)"; \
		echo "$(YELLOW)  install: uv tool install check-jsonschema$(RESET)"; \
		exit 0; \
	fi; \
	if [ ! -f "$(SKELETON_SKILL)/SKILL.md" ]; then \
		echo "$(YELLOW)agentic-skeleton not installed at $(SKELETON_SKILL) — schema check skipped.$(RESET)"; \
		echo "$(YELLOW)  override with: make ci-vibe SKELETON_SKILL=/path/to/agentic-skeleton$(RESET)"; \
		exit 0; \
	fi; \
	python3 scripts/validate_vibe_yaml.py --skills-dir "$(SKELETON_SKILL)"

## ci-shell: shellcheck every shell script in the repo
ci-shell:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "$(YELLOW)shellcheck not installed — shell lint skipped (uv tool install shellcheck-py).$(RESET)"; \
		exit 0; \
	fi; \
	files=$$(git ls-files --cached --others --exclude-standard '*.sh' '.githooks/*' 2>/dev/null); \
	if [ -z "$$files" ]; then \
		files=$$(find . -path ./.git -prune -o -name '*.sh' -print 2>/dev/null; \
		         find .githooks -type f 2>/dev/null); \
	fi; \
	[ -n "$$files" ] || { echo "  no shell scripts found"; exit 0; }; \
	echo "$$files" | tr '\n' ' ' | sed 's/^/  /'; echo ""; \
	shellcheck -x $$files

## ci-ruby: `ruby -c` every fastlane configuration file
ci-ruby:
	@if ! command -v ruby >/dev/null 2>&1; then \
		echo "$(YELLOW)ruby not installed — fastlane syntax check skipped.$(RESET)"; \
		exit 0; \
	fi; \
	bad=0; \
	for f in fastlane/*ile; do \
		[ -f "$$f" ] || continue; \
		if ruby -c "$$f" >/dev/null 2>&1; then \
			echo "  ok   $$f"; \
		else \
			echo "$(RED)  FAIL $$f$(RESET)"; ruby -c "$$f" 2>&1 | sed 's/^/       /'; \
			bad=$$((bad+1)); \
		fi; \
	done; \
	[ "$$bad" -eq 0 ] || { echo "$(RED)$$bad fastlane file(s) have syntax errors.$(RESET)"; exit 1; }

## ci-yamllint: Style-lint YAML when yamllint is installed
ci-yamllint:
	@if ! command -v yamllint >/dev/null 2>&1; then \
		echo "$(YELLOW)yamllint not installed — YAML style lint skipped.$(RESET)"; \
		exit 0; \
	fi; \
	files=""; \
	for f in $(CI_YAML_GLOBS); do [ -f "$$f" ] && files="$$files $$f"; done; \
	[ -n "$$files" ] || { echo "  nothing to lint"; exit 0; }; \
	yamllint -d relaxed $$files

## check-no-serena: ADR-0005 guard — `make sync-skeleton --apply` can silently
## re-introduce the skeleton's Serena files; this catches them before commit.
.PHONY: check-no-serena
check-no-serena:
	@bad=0; \
	for f in .claude/hooks/serena-required.sh .claude/hooks/serena-gate.sh .claude/rules/serena.md; do \
		if [ -e "$$f" ]; then echo "$(RED)  FAIL Serena file present: $$f (ADR-0005; delete it — likely sync-skeleton fallout)$(RESET)"; bad=1; fi; \
	done; \
	if grep -q '"serena"' .mcp.json 2>/dev/null; then echo "$(RED)  FAIL serena server in .mcp.json (ADR-0005)$(RESET)"; bad=1; fi; \
	if grep -rql "serena" .claude/settings.json 2>/dev/null; then echo "$(RED)  FAIL serena wiring in settings.json (ADR-0005)$(RESET)"; bad=1; fi; \
	[ "$$bad" -eq 0 ] && echo "  ok   no Serena files, servers, or wiring" || exit 1
