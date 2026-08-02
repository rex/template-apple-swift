# ADR 0003 — CI posture: free Linux gates + manual-dispatch macOS compile matrix

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner)
- **Scope:** CI for this template repo; CI defaults for generated repos

## Context

macOS GitHub runners bill ~10× Linux minutes on private repos. The template's
correctness has two layers: structural (generator tests, manifest/marker
consistency, YAML/schema validity, shellcheck — all runnable on Linux) and
compile truth (xcodegen + xcodebuild — macOS only). The tool-ci skill's `ci:`
namespace defaults `runner_pattern: docker`, which cannot host Xcode.

## Decision

- **`ci.yml`** (ubuntu, every push/PR, concurrency-cancel): generator pytest,
  6-combo generate+verify structural matrix, `make ci-linux` (the repo's own
  gates — never a CI-side reimplementation), docs-consistency checks.
- **`verify-macos.yml`** (`workflow_dispatch` only): 6-config matrix — superset
  as committed, minimal, ios-widgets-la, ios-watch, universal, no-health — each
  generated then `xcodegen` + `xcodebuild build` (`CODE_SIGNING_ALLOWED=NO`) +
  `make test`/`ui-test` where applicable. Run on demand and always before a
  template version tag. A green matrix is the release gate.
- VIBE records `ci.runner_pattern: setup-actions` with this ADR as rationale
  (docker default unusable for Xcode).
- Generated repos choose at onboarding: `xcode_cloud` (default; `ci_scripts/`
  path), `github_actions` (installs `release.yml` payload + test workflow), or
  `none`.
- All workflows SHA-pin third-party actions and expose `workflow_dispatch`
  (tool-ci hard rules).

## Consequences

- Compile regressions can land on the branch between macOS runs; the tag gate
  (full matrix green) is the compile-truth backstop, and `verify-macos` is
  cheap to dispatch on demand.
- Template maintenance cost stays near zero for day-to-day pushes.
