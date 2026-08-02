# ADR 0008 — Skeleton sync boundary: Apple additions are net-new files only

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner), Fable
- **Scope:** How this template coexists with `/sync-skills` and
  `make sync-skeleton` (resolves C3, C4; records the dead-weight trade-off)

## Context

The skeleton's propagation machinery classifies files: **Verbatim**
(all `scripts/` gate pythons and everything under
`.claude/{hooks,commands,agents,rules}/` — blind-copied on sync), **Advisory**
(`Makefile`, `.pre-commit-config.yaml`, `.claude/settings.json` — drift
reported, reconciled by judgment), and **Orphan** (local files with no skill
counterpart — reported, never touched). Any local EDIT to a Verbatim file is
clobbered by the next sync.

## Decision

Every Apple-specific addition to skeleton-owned directories ships as a
**net-new file** (sync-safe Orphan), never as an edit to a Verbatim file:
`hooks/session-start-apple.sh` (second SessionStart entry — C3),
`hooks/auto-lint-swift.sh` (second PostToolUse entry — C4), `rules/swift.md`,
`commands/{onboard,release,grade-north-star}.md`,
`agents/{apple-reviewer,xcode-build-debugger}.md`, `skills/release-ops/`.
Wiring lives in `settings.json` (Advisory — expected to carry local wiring).
Serena's Verbatim files are excluded at copy time per ADR-0005. The skeleton's
Apple-irrelevant Verbatim files (terraform/ansible rules and commands,
terraform-reviewer agent) are **kept** — dropping them would make every sync
re-add them; the correct removal is upstream in the skeleton (tracked in the
Phase-6 proposal, alongside proposals to upstream a Swift branch in
auto-lint.sh and an xcodebuild rung in test-runner's ladder).

## Consequences

- `/sync-skills` and `make sync-skeleton` stay safe to run in generated repos.
- Apple repos carry a few irrelevant terraform/ansible files until the skeleton
  itself changes — accepted interim noise.
- If the skeleton later ships its own versions of our net-new filenames, the
  sync classes collide — the skill-update proposal flags the names for
  reservation.
