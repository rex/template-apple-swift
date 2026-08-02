# ADR 0007 — Version contract: semver VERSION file, xcconfig injection

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner), Fable
- **Scope:** Resolves the skeleton-vs-Apple VERSION file conflict (C1)

## Context

Two incompatible formats claim the `VERSION` path. The agentic-skeleton
standard: a one-line semver string gated by `bump_version.py` /
`check_version_bumped.py` (`make bump-patch/minor/major`). The lang-swift-apple
0.3.0 pattern (as deployed in Pennywise): `MAJOR=`/`MINOR_BASE=` parsed by awk
in four scripts, with a pre-commit hook auto-bumping `MINOR_BASE` every commit
and CI computing `minor = MINOR_BASE + commit-distance`. Pennywise additionally
shows the failure mode of stamping versions into project.yml literals:
indentation-sensitive awk patches and a hardcoded `CFBundleVersion` that CI
never reaches.

## Decision

**Skeleton semver wins.** `VERSION` contains a plain semver string (initial
`0.1.0`); the skeleton bump/check gates apply unchanged
(`versioning.bump_required_per_commit: true` — the pre-commit hook runs
`check-version-bumped`, humans/agents bump intentionally; no auto-increment).
Apple mapping at build/release time only:
`MARKETING_VERSION := $(cat VERSION)` and
`CURRENT_PROJECT_VERSION := $(git rev-list --count HEAD)`, materialized
exclusively into `Config/Versions.xcconfig` (per ADR-0006) by
`ci_scripts/ci_post_clone.sh` (Xcode Cloud), the fastlane lanes
(github_actions/local release), and `make bootstrap` (dev convenience).
`scripts/apple/generate-build-info.sh` reads the same sources for the in-app
`BuildInfo.swift`. The MAJOR/MINOR_BASE format, its awk parsers, and the
MINOR_BASE auto-bump hook are not carried forward.

## Consequences

- One version discipline across Pierce's whole repo fleet; Apple specificity
  is confined to the xcconfig materialization step.
- Build numbers are monotonic by construction (commit count).
- lang-swift-apple's VERSION section needs a skill update (tracked in the
  Phase-6 skill-update proposal).
