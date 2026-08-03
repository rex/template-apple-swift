# ╔══════════════════════════════════════════════════════════════════════╗
# ║          MyApp — Makefile                                            ║
# ║          Swift 6 · SwiftUI · xcodegen · iOS / macOS / watchOS        ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# Usage: make <target>   ·   `make help` lists everything.
#
# One interface, split by responsibility (the whole thing is `make help`):
#   this file        configuration + the Apple verbs (build / test / audit)
#   make/help.mk     the hand-crafted help target
#   make/gates.mk    the agentic-skeleton contract gates + versioning
#   make/release.mk  1:1 fastlane lane delegation (contracts §8)
#   make/ci.mk       `ci-linux` — every gate that runs without Xcode
#
# Compile truth is macOS-only (ADR-0003): every xcodebuild-dependent target
# says so out loud instead of pretending to pass.

.PHONY: bootstrap setup regenerate env env-check \
        build build-ios build-watch build-mac build-all \
        test ui-test typecheck lint audit \
        spinner-sync spinner-check clean info

# ─── Configuration ────────────────────────────────────────────────────
# Prefer Homebrew zsh on macOS, then any zsh on PATH, then /bin/bash as
# a CI-runner fallback (most CI runners don't ship zsh by default;
# without this third fallback SHELL resolves to '' and `make: -c: No
# such file or directory` fires on the first recipe). Keep recipes
# POSIX-compatible — no `[[ ]]`, no `${var//foo/bar}` substitution, no
# zsh globbing — so /bin/bash works as a true fallback.
SHELL       := $(or $(wildcard /opt/homebrew/bin/zsh),$(shell command -v zsh),/bin/bash)

APP_NAME     ?= MyApp
PROJECT      ?= MyApp.xcodeproj
SCHEME       ?= MyApp
SCHEME_MAC   ?= MyAppMac
SCHEME_WATCH ?= MyAppWatch
SCHEME_UI    ?= MyAppScreenshots

# Simulator names are runner-image-coupled (ADR-0003): these are the macos-26
# defaults. scripts/apple/pick-simulator.sh falls back to the newest installed
# model when the named one is absent, so overriding is optional:
#   make test DEVICE='iPhone 17 Pro'
DEVICE       ?= iPhone 17
WATCH_DEVICE ?= Apple Watch Series 11 (46mm)

# Destinations. Builds use generic destinations (no simulator needs to exist);
# only test/ui-test name a concrete device, resolved at run time.
#
# DEST_IOS_TEST is RECURSIVELY assigned (`=`, not `:=`) for two reasons: the
# `$$(...)` must survive make's expansion and reach the shell as a command
# substitution, and a command-line `DEVICE=` override must still win. It also
# has to be a variable rather than inline text because `$(call ...)` splits its
# arguments on commas — and this value contains one.
DEST_IOS_BUILD   := generic/platform=iOS Simulator
DEST_WATCH_BUILD := generic/platform=watchOS Simulator
DEST_MAC_BUILD   := generic/platform=macOS
DEST_IOS_TEST     = platform=iOS Simulator,name=$$(./scripts/apple/pick-simulator.sh ios '$(DEVICE)')

XCODEGEN   ?= xcodegen
XCODEBUILD ?= xcodebuild
FASTLANE   ?= bundle exec fastlane
RESULTS    ?= build/results
NOSIGN     := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# Component probes: a pruned repo has no MyAppWatch/ or MyAppMac/ directory,
# so `make build-all` must skip those platforms instead of failing. These are
# the same directories components.yaml lists under owns.dirs.
HAS_WATCH := $(wildcard MyAppWatch)
HAS_MAC   := $(wildcard MyAppMac)

# Colors for output
CYAN   := $(shell printf '\033[36m')
GREEN  := $(shell printf '\033[32m')
YELLOW := $(shell printf '\033[33m')
RED    := $(shell printf '\033[31m')
RESET  := $(shell printf '\033[0m')
BOLD   := $(shell printf '\033[1m')

# ─── Shared recipe fragments ──────────────────────────────────────────
# Each define is ONE logical shell line (backslash continuations), so it can
# be `$(call ...)`ed from a tab-indented recipe line.

# Run an xcodebuild invocation, prettified by xcbeautify when installed.
# `set -o pipefail` keeps xcodebuild's exit status alive through the pipe —
# without it a failed build reports xcbeautify's success instead.
define xcbuild
@if command -v xcbeautify >/dev/null 2>&1; then \
	set -o pipefail; $(1) | xcbeautify; \
else \
	$(1); \
fi
endef

define require_xcodebuild
@command -v $(XCODEBUILD) >/dev/null 2>&1 || { \
	echo "$(RED)xcodebuild not found — this target needs macOS with Xcode 26.$(RESET)"; \
	echo "$(RED)Compile truth is macOS-only (ADR-0003). On Linux run 'make ci-linux',$(RESET)"; \
	echo "$(RED)or dispatch .github/workflows/verify-macos.yml.$(RESET)"; \
	exit 1; }
endef

define require_xcodegen
@command -v $(XCODEGEN) >/dev/null 2>&1 || { \
	echo "$(RED)xcodegen not found — the .xcodeproj is generated, never committed.$(RESET)"; \
	echo "$(RED)Install it: brew install xcodegen  (>= 2.46.0, see project.yml).$(RESET)"; \
	exit 1; }
endef

# ─── Setup ────────────────────────────────────────────────────────────

## regenerate: Stamp versions and regenerate the .xcodeproj (fast, idempotent)
regenerate:
	$(require_xcodegen)
	@./scripts/apple/write-versions.sh
	@$(XCODEGEN) generate

## bootstrap: One command from fresh clone to buildable project
bootstrap: regenerate
	@echo "$(CYAN)git hooks$(RESET)"
	@if command -v pre-commit >/dev/null 2>&1; then \
		pre-commit install; \
	else \
		echo "$(YELLOW)  pre-commit not installed — it is MANDATORY here.$(RESET)"; \
		echo "$(YELLOW)  Install it: uv tool install pre-commit, then re-run.$(RESET)"; \
	fi
	@HOOKS=$$(git rev-parse --git-path hooks 2>/dev/null); \
	if [ -n "$$HOOKS" ] && [ -d "$$HOOKS" ]; then \
		cp .githooks/post-commit "$$HOOKS/post-commit"; \
		chmod +x "$$HOOKS/post-commit"; \
		echo "  post-commit auto-push hook installed"; \
	else \
		echo "$(YELLOW)  no .git/hooks here — skipping post-commit hook$(RESET)"; \
	fi
	@echo "$(CYAN)ruby gems (fastlane)$(RESET)"
	@if command -v bundle >/dev/null 2>&1; then \
		bundle install --quiet && echo "  gems ready"; \
	else \
		echo "$(YELLOW)  ruby/bundler absent — release lanes unavailable until 'bundle install'$(RESET)"; \
	fi
	@echo "$(GREEN)Bootstrap complete. Open $(PROJECT), or run 'make build'.$(RESET)"

## setup: Alias for bootstrap (agentic-skeleton universal interface)
setup: bootstrap

## env: Create .env from .env.example if missing
env:
	@if [ ! -f .env ]; then \
		if [ -f .env.example ]; then \
			cp .env.example .env; \
			echo "$(GREEN).env created from .env.example. Fill it in before releasing.$(RESET)"; \
		else \
			echo "$(RED)No .env.example to copy from.$(RESET)"; exit 1; \
		fi \
	else \
		echo "$(YELLOW).env already exists, skipping.$(RESET)"; \
	fi

## env-check: Verify .env exists
env-check:
	@if [ ! -f .env ]; then echo "$(RED).env missing — run 'make env'.$(RESET)"; exit 1; fi
	@echo "$(GREEN).env present.$(RESET)"

# ─── Build ────────────────────────────────────────────────────────────
# Builds use generic destinations: no simulator needs to exist, nothing boots,
# and signing is off. Only test/ui-test name a concrete device.

## build: Build the iOS app (alias for build-ios)
build: build-ios

## build-ios: Build the iOS app for the simulator SDK
build-ios: regenerate
	$(require_xcodebuild)
	@echo "$(CYAN)Building $(SCHEME) (iOS Simulator)...$(RESET)"
	$(call xcbuild,$(XCODEBUILD) build -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DEST_IOS_BUILD)' $(NOSIGN))

## build-watch: Build the watchOS app (skipped when the watch component is off)
build-watch: regenerate
ifeq ($(HAS_WATCH),)
	@echo "$(YELLOW)No MyAppWatch/ — watch component pruned, skipping build-watch.$(RESET)"
else
	$(require_xcodebuild)
	@echo "$(CYAN)Building $(SCHEME_WATCH) (watchOS Simulator)...$(RESET)"
	$(call xcbuild,$(XCODEBUILD) build -project $(PROJECT) -scheme $(SCHEME_WATCH) \
		-destination '$(DEST_WATCH_BUILD)' $(NOSIGN))
endif

## build-mac: Build the macOS app (skipped when the mac component is off)
build-mac: regenerate
ifeq ($(HAS_MAC),)
	@echo "$(YELLOW)No MyAppMac/ — mac component pruned, skipping build-mac.$(RESET)"
else
	$(require_xcodebuild)
	@echo "$(CYAN)Building $(SCHEME_MAC) (macOS)...$(RESET)"
	$(call xcbuild,$(XCODEBUILD) build -project $(PROJECT) -scheme $(SCHEME_MAC) \
		-destination '$(DEST_MAC_BUILD)' $(NOSIGN))
endif

## build-all: Build every platform this repo still has
build-all: build-ios build-watch build-mac
	@echo "$(GREEN)All present platforms built.$(RESET)"

# ─── Test ─────────────────────────────────────────────────────────────

## test: Run the unit-test bundle on a booted iOS simulator
test: regenerate
	$(require_xcodebuild)
	@rm -rf $(RESULTS)/$(SCHEME).xcresult
	@mkdir -p $(RESULTS)
	@echo "$(CYAN)Testing $(SCHEME) on '$(DEVICE)'...$(RESET)"
	$(call xcbuild,$(XCODEBUILD) test -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$(DEST_IOS_TEST)" \
		-resultBundlePath $(RESULTS)/$(SCHEME).xcresult $(NOSIGN))

## ui-test: Run the UI tests (the same scheme fastlane snapshot drives)
ui-test: regenerate
	$(require_xcodebuild)
	@rm -rf $(RESULTS)/$(SCHEME_UI).xcresult
	@mkdir -p $(RESULTS)
	@echo "$(CYAN)UI-testing $(SCHEME_UI) on '$(DEVICE)'...$(RESET)"
	$(call xcbuild,$(XCODEBUILD) test -project $(PROJECT) -scheme $(SCHEME_UI) \
		-destination "$(DEST_IOS_TEST)" \
		-resultBundlePath $(RESULTS)/$(SCHEME_UI).xcresult $(NOSIGN))

## typecheck: Compile everything the tests need, run nothing
typecheck: regenerate
	$(require_xcodebuild)
	@echo "$(CYAN)Type-checking $(SCHEME)...$(RESET)"
	$(call xcbuild,$(XCODEBUILD) build-for-testing -quiet -project $(PROJECT) \
		-scheme $(SCHEME) -destination '$(DEST_IOS_BUILD)' $(NOSIGN))

# ─── Quality ──────────────────────────────────────────────────────────

## lint: SwiftLint + shellcheck when installed, plus the fail-closed architecture gate
lint: check-architecture ci-shell
	@if command -v swiftlint >/dev/null 2>&1; then \
		echo "$(CYAN)Running SwiftLint...$(RESET)"; \
		swiftlint lint --quiet; \
	else \
		echo "$(YELLOW)swiftlint not installed — style pass skipped (brew install swiftlint).$(RESET)"; \
		echo "$(YELLOW)The architecture gate above still ran and is the fail-closed part.$(RESET)"; \
	fi

## audit: App Store compliance + Apple-shaped secret scan
audit:
	@echo "$(CYAN)Auditing...$(RESET)"
	@./scripts/apple/audit-privacy-manifest.sh
	@./scripts/apple/audit-usage-descriptions.sh
	@./scripts/apple/check-no-cocoapods.sh
	@./scripts/apple/scan-plist-secrets.sh

## spinner-sync: Materialize the spinner corpus into .claude/settings.json
spinner-sync:
	@if [ ! -f scripts/sync_spinner_verbs.py ]; then \
		echo "$(YELLOW)scripts/sync_spinner_verbs.py absent — spinner flavor not installed.$(RESET)"; \
		exit 0; \
	fi; \
	if command -v uv >/dev/null 2>&1; then \
		uv run scripts/sync_spinner_verbs.py; \
	else \
		python3 scripts/sync_spinner_verbs.py; \
	fi

## spinner-check: Fail when settings.json drifts from the corpus files
spinner-check:
	@if [ ! -f scripts/sync_spinner_verbs.py ]; then \
		echo "$(YELLOW)scripts/sync_spinner_verbs.py absent — spinner flavor not installed, skipping.$(RESET)"; \
		exit 0; \
	fi; \
	if command -v uv >/dev/null 2>&1; then \
		uv run scripts/sync_spinner_verbs.py --check; \
	else \
		python3 scripts/sync_spinner_verbs.py --check; \
	fi

# ─── Maintenance ──────────────────────────────────────────────────────

## clean: Remove build output and the generated project
clean:
	@echo "$(CYAN)Cleaning...$(RESET)"
	@rm -rf build/ DerivedData/ $(PROJECT) fastlane/test_output
	@echo "$(GREEN)Clean. Run 'make bootstrap' to regenerate the project.$(RESET)"

## info: Show project state
info:
	@echo "$(BOLD)$(CYAN)$(APP_NAME)$(RESET)"
	@echo "──────────────────────────────"
	@echo "  Version:  $$(cat VERSION 2>/dev/null || echo 'VERSION missing')"
	@echo "  Build:    $$(git rev-list --count HEAD 2>/dev/null || echo 'n/a')"
	@echo "  Branch:   $$(git branch --show-current 2>/dev/null || echo 'n/a')"
	@echo "  Commit:   $$(git rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
	@echo "  Tree:     $$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ') uncommitted change(s)"
	@echo "  Xcode:    $$(xcodebuild -version 2>/dev/null | head -1 || echo 'not installed (Linux)')"
	@echo "  Targets:  $$(ls -d MyApp MyAppMac MyAppWatch HomeWidget MacWidget LiveActivity \
		WatchComplications NotificationService 2>/dev/null | tr '\n' ' ')"

include make/help.mk
include make/gates.mk
include make/release.mk
include make/ci.mk

.DEFAULT_GOAL := help
