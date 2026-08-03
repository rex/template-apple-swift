# make/gates.mk — the agentic-skeleton contract targets.
#
# These are the gates every Pierce repo has, wired to this repo's real tools.
# They are deliberately identical in NAME and SEMANTICS across the fleet, so an
# agent that knows `make validate` knows it here. A gate whose script is
# missing FAILS — never skips — because a gate that does not run is a failure,
# not a pass. The one exception is documented inline: `spinner-check` (root
# Makefile) tolerates its script being absent, because the generator legitimately
# deletes it when `ops.spinner_flavor` is false.

.PHONY: validate verify check-architecture check-docs check-links check-precommit \
        check-skeleton sync-skeleton check-skills stamp-skill \
        version bump-patch bump-minor bump-major check-version-bumped \
        check-if-the-agent-can-consider-this-task-completed

# Where the installed agentic-skeleton skill lives (validate_vibe_yaml.py needs
# its schema doc). Override when yours is elsewhere.
SKELETON_SKILL ?= $(HOME)/.claude/skills/agentic-skeleton

## validate: Run the repo's aggregate validation flow
validate: lint typecheck check-architecture check-version-bumped check-skills
	@echo "$(GREEN)Validation complete.$(RESET)"

# ─── Architecture + docs ──────────────────────────────────────────────

## check-architecture: Enforce VIBE.yaml line limits + module shape (fails closed)
check-architecture:
	@echo "$(CYAN)Checking architecture (line limits + module shape)...$(RESET)"
	@for s in check_architecture.py check_module_rules.py; do \
		if [ ! -f "scripts/$$s" ]; then \
			echo "$(RED)  scripts/$$s is MISSING — the architecture gate$(RESET)"; \
			echo "$(RED)  cannot run. Hard failure, never a skip. Restore it:$(RESET)"; \
			echo "$(RED)  re-run the agentic-skeleton bootstrap.$(RESET)"; \
			exit 1; \
		fi; \
	done
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/check_architecture.py && uv run scripts/check_module_rules.py; \
	elif python3 -c 'import yaml' >/dev/null 2>&1; then \
		python3 scripts/check_architecture.py && python3 scripts/check_module_rules.py; \
	else \
		echo "$(RED)  Architecture gate cannot run: no 'uv', and no$(RESET)"; \
		echo "$(RED)  python3 with PyYAML. Install uv: https://docs.astral.sh/uv/$(RESET)"; \
		exit 1; \
	fi

## check-docs: Enforce VIBE.yaml docs.*_required (fails closed)
check-docs:
	@echo "$(CYAN)Checking required collaboration files (VIBE.yaml docs)...$(RESET)"
	@if [ ! -f scripts/check_docs.py ]; then \
		echo "$(RED)  scripts/check_docs.py is MISSING — the docs gate$(RESET)"; \
		echo "$(RED)  cannot run. Hard failure. Re-run the bootstrap.$(RESET)"; \
		exit 1; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/check_docs.py; \
	elif python3 -c 'import yaml' >/dev/null 2>&1; then \
		python3 scripts/check_docs.py; \
	else \
		echo "$(RED)  docs gate cannot run: no 'uv', no python3 + PyYAML.$(RESET)"; \
		exit 1; \
	fi

## check-links: Every relative link in a markdown file points at something real
check-links:
	@echo "$(CYAN)Checking relative links in markdown...$(RESET)"
	@broken=0; \
	files=$$(git ls-files --cached --others --exclude-standard '*.md' 2>/dev/null); \
	if [ -z "$$files" ]; then \
		files=$$(find . -name '*.md' -not -path './.git/*' | sed 's|^\./||'); \
	fi; \
	for f in $$files; do \
		dir=$$(dirname "$$f"); \
		for link in $$(grep -oE '\]\([^)#][^) ]*\)' "$$f" 2>/dev/null \
			| sed -E 's/^\]\(//; s/\)$$//' | grep -vE '^[a-zA-Z][a-zA-Z0-9+.-]*:' | sed 's/#.*//'); do \
			[ -n "$$link" ] || continue; \
			case "$$link" in \
				/*) target=".$$link" ;; \
				*)  target="$$dir/$$link" ;; \
			esac; \
			if [ ! -e "$$target" ]; then \
				echo "$(RED)  ✗ $$f → $$link$(RESET)"; \
				broken=$$((broken+1)); \
			fi; \
		done; \
	done; \
	if [ "$$broken" -gt 0 ]; then \
		echo "$(RED)$$broken broken relative link(s). Fix the link or restore the file.$(RESET)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)  every relative markdown link resolves.$(RESET)"

# ─── Enforcement surface ──────────────────────────────────────────────

## check-precommit: Verify the pre-commit hook is installed (fails closed)
check-precommit:
	@echo "$(CYAN)Checking the pre-commit enforcement surface...$(RESET)"
	@if [ ! -f .pre-commit-config.yaml ]; then \
		echo "$(RED)  .pre-commit-config.yaml is MISSING — the commit-time$(RESET)"; \
		echo "$(RED)  enforcement surface is absent. Re-run the bootstrap.$(RESET)"; \
		exit 1; \
	fi
	@if ! command -v pre-commit >/dev/null 2>&1; then \
		echo "$(RED)  pre-commit is not installed — it is MANDATORY, not$(RESET)"; \
		echo "$(RED)  optional. Install it: uv tool install pre-commit$(RESET)"; \
		exit 1; \
	fi
	@HOOK=$$(git rev-parse --git-path hooks/pre-commit 2>/dev/null); \
	if [ -z "$$HOOK" ] || [ ! -f "$$HOOK" ] || ! grep -q pre-commit "$$HOOK" 2>/dev/null; then \
		echo "$(RED)  the pre-commit git hook is NOT installed. Run:$(RESET)"; \
		echo "$(RED)    pre-commit install    (or: make bootstrap)$(RESET)"; \
		echo "$(RED)  A .pre-commit-config.yaml with no installed hook$(RESET)"; \
		echo "$(RED)  enforces nothing — fail closed.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)  pre-commit hook installed.$(RESET)"

## check-skeleton: Report drift vs the installed agentic-skeleton
check-skeleton:
	@echo "$(CYAN)Checking skeleton-owned files for drift...$(RESET)"
	@if [ ! -f scripts/sync_skeleton.py ]; then \
		echo "$(RED)  scripts/sync_skeleton.py is MISSING — cannot check$(RESET)"; \
		echo "$(RED)  skeleton drift. Re-run the agentic-skeleton bootstrap.$(RESET)"; \
		exit 1; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/sync_skeleton.py --check; \
	else \
		python3 scripts/sync_skeleton.py --check; \
	fi

## sync-skeleton: Pull current skeleton-owned files into this repo
sync-skeleton:
	@if [ ! -f scripts/sync_skeleton.py ]; then \
		echo "$(RED)  scripts/sync_skeleton.py is MISSING.$(RESET)"; \
		exit 1; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/sync_skeleton.py --apply; \
	else \
		python3 scripts/sync_skeleton.py --apply; \
	fi

## check-skills: Advisory applied-skill provenance + drift report (never fails)
check-skills:
	@echo "$(CYAN)Checking applied-skill provenance...$(RESET)"
	@if [ ! -f scripts/check_skills.py ]; then \
		echo "$(YELLOW)  scripts/check_skills.py not present — run 'make sync-skeleton'.$(RESET)"; \
	elif command -v uv >/dev/null 2>&1; then \
		uv run scripts/check_skills.py || true; \
	else \
		python3 scripts/check_skills.py || true; \
	fi

## stamp-skill: Record that a skill was applied (SKILL=<id> [VERSION=x.y.z])
stamp-skill:
	@if [ -z "$(SKILL)" ]; then \
		echo "$(RED)Usage: make stamp-skill SKILL=<id> [VERSION=x.y.z]$(RESET)"; exit 1; \
	fi
	@if [ ! -f scripts/stamp_skill.py ]; then \
		echo "$(RED)  scripts/stamp_skill.py missing — run 'make sync-skeleton'.$(RESET)"; exit 1; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		uv run scripts/stamp_skill.py "$(SKILL)" $(if $(VERSION),--version "$(VERSION)"); \
	else \
		python3 scripts/stamp_skill.py "$(SKILL)" $(if $(VERSION),--version "$(VERSION)"); \
	fi

# ─── Versioning (ADR-0007: plain semver, no auto-bump) ────────────────
# VERSION is the source of truth for MARKETING_VERSION; the build number is
# `git rev-list --count HEAD`. Both are materialized into
# Config/Versions.xcconfig by scripts/apple/write-versions.sh — never into
# project.yml, which an .xcconfig can never override.

## version: Print current VERSION
version:
	@cat VERSION 2>/dev/null || echo "0.1.0 (VERSION file missing)"

## bump-patch: Increment patch (x.y.Z+1) — ONLY inarguably trivial doc-only
## changes (Pierce, 2026-08-03). Everything else — fixes, features, config,
## scripts, CI — is `bump-minor`. When in doubt, minor.
bump-patch:
	@scripts/bump_version.py patch

## bump-minor: Increment minor (x.Y+1.0) — additive features, backward-compatible
bump-minor:
	@scripts/bump_version.py minor

## bump-major: Increment major (X+1.0.0) — breaking change, removal, incompat behavior
bump-major:
	@scripts/bump_version.py major

## check-version-bumped: Fail if VERSION == HEAD's VERSION or CHANGELOG lacks matching entry
check-version-bumped:
	@if [ ! -f scripts/check_version_bumped.py ]; then \
		echo "$(RED)scripts/check_version_bumped.py is MISSING — the version$(RESET)"; \
		echo "$(RED)gate cannot run. Hard failure, never a skip — re-run the$(RESET)"; \
		echo "$(RED)agentic-skeleton bootstrap to restore it.$(RESET)"; \
		exit 1; \
	fi
	@python3 scripts/check_version_bumped.py

# ─── Completion Gate ──────────────────────────────────────────────────

## verify: The full gate chain (macOS) — alias for the completion gate
verify: check-if-the-agent-can-consider-this-task-completed

## check-if-the-agent-can-consider-this-task-completed: Final verification gate
check-if-the-agent-can-consider-this-task-completed: validate check-docs check-precommit test
	@echo ""
	@echo "$(BOLD)$(GREEN)✓ All gates passed. Task may be declared complete.$(RESET)"
	@echo ""
	@if [ -n "$$(git status --porcelain 2>/dev/null)" ]; then \
		echo "$(YELLOW)NOTE: working tree is dirty:$(RESET)"; \
		git status --short; \
		echo ""; \
		echo "$(YELLOW)The gates passed, but VIBE.yaml clean_worktree_required_on_completion$(RESET)"; \
		echo "$(YELLOW)may still apply. Commit or stash before declaring done.$(RESET)"; \
	fi
