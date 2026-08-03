# Changelog

All notable changes to this project are documented here. This project
follows [Semantic Versioning](https://semver.org/) and
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Format:

```markdown
## [X.Y.Z] — YYYY-MM-DD — Agent: <name>
### Added | Changed | Fixed | Removed | Deprecated | Security
- <what changed, in imperative voice>
```

**Every commit requires a version bump and a matching entry here.** The
`scripts/check_version_bumped.py` gate enforces this; `auto-commit.sh`
calls `scripts/bump_version.py <level>` before commit.

**Bump level guidance** (agent decides per slice):
- `patch` — bug fix, documentation change, refactor with no behavior change
- `minor` — new feature, new public API, any backward-compatible addition
- `major` — breaking change, removal, incompatible behavior change

**Agent attribution is required.** Every entry names the agent (or human)
that authored the change. This is how we keep `git blame` honest when
multiple agents and humans work on the same slice.

Append new entries at the top. One entry per commit (same cadence as
version bumps).

> **Note for stamped apps.** This file is NOT reset at onboarding. Entries
> above `0.1.0` belong to the template's own construction history. Either keep
> them as provenance, or truncate everything below your first app entry — both
> are fine, but decide once.

---

## [0.4.0] — 2026-08-03 — Agent: Claude

### Fixed
- verify-macos run #3: the three Checkpoint intents and `MyAppShortcuts` were
  declared `nonisolated struct`, and a type-level `nonisolated` distributes
  onto `@Parameter`/`@Dependency` — mutable stored properties, which the
  compiler rejects ("'nonisolated' cannot be applied to mutable stored
  properties"). All four App Intents types are now `@MainActor`; their
  `static let` metadata still witnesses the nonisolated protocol
  requirements (immutable + Sendable) and `perform()` is an async
  requirement, so the isolated witness is legal.

### Added
- FORBIDDEN gate pattern: `nonisolated` on an App Intents type declaration
  (`AppIntent`, `AppShortcutsProvider`, `WidgetConfigurationIntent`,
  `ControlConfigurationIntent`) now fails `template/verify.py` on Linux, so
  this class of compile failure never reaches a macOS runner again.
- `.claude/rules/swift.md`: concurrency bullet codifying the rule.

## [0.3.0] — 2026-08-03 — Agent: Claude

### Fixed
- First real Swift 6 compile failure (verify-macos run #2): an unannotated
  `extension Color` in ColorHex.swift became MainActor-isolated under
  SWIFT_DEFAULT_ACTOR_ISOLATION, unreachable from the nonisolated palette
  statics (8 errors, every Theme-bearing target). All five first-party
  extensions in Shared/ now carry explicit `nonisolated`/`@MainActor`.

### Added
- `checks_swift.extension_isolation`: verify.py now fails any Shared/
  extension lacking explicit isolation — the gap the self-checks had (types
  were checked; extensions were not). Rides into every generated repo.

## [0.2.0] — 2026-08-03 — Agent: Claude

### Changed
- Version-bump policy encoded (VIBE.yaml, CONVENTIONS.md, make help text):
  patch = inarguably trivial doc-only changes ONLY; everything else = minor.
  0.2.0 also rebaselines the ledger — 0.1.1 (CI gate fixes) and 0.1.3
  (bash-3.2 script fixes) warranted minors under this policy.

## [0.1.4] — 2026-08-03 — Agent: Claude

### Fixed
- README + generated-README fragment pointed clones at the wrong GitHub owner
  (piercemoore/ instead of rex/) — caught by the go-public audit.

## [0.1.3] — 2026-08-03 — Agent: Claude

### Fixed
- macOS bash-3.2 compatibility across scripts/apple/: heredocs nested inside
  command substitution (write-versions, generate-build-info — the parser
  quote-scans heredoc bodies, so an apostrophe reads as an unclosed string and
  killed all six verify-macos jobs in under a minute) and `mapfile` (a bash-4
  builtin) in scan-plist-secrets + both audits, replaced with while-read
  loops. verify-macos run #1 never reached xcodegen; this unblocks run #2.

## [0.1.2] — 2026-08-02 — Agent: Claude

### Changed
- TASK_STATE: S4 closed green (ci.yml run #4 all-jobs success on GitHub
  runners); S5 Mac-verification loop opened with the dispatch-permission
  handoff recorded.

## [0.1.1] — 2026-08-02 — Agent: Claude

### Fixed
- ci-shell gates at `shellcheck -S warning` — info/style notes (e.g. SC2015 in
  the skeleton-verbatim `auto-lint.sh`) are review signal, not build failures.
- Repaired the ci-shell recipe after comment lines broke its continuation
  chain ("No files specified").

### Changed
- Wave-2 integration gate: junction includes ratified, `pre-compact-apple.sh`
  rename, `check-no-serena` ci-linux guard, `Versions.xcconfig` untracked,
  spinner corpus materialized (194 verbs + 37 tips), `APPLE_ID_AUTH`
  capability fix, VIBE excludes for template machinery.


## [0.1.0] — 2026-08-02 — Agent: Claude
### Added
- Superset Apple app: iOS, macOS and watchOS app targets plus home widgets,
  a Mac widget, a Live Activity, Watch complications and a Notification
  Service Extension — ten targets from one XcodeGen manifest.
- One-shot onboarding generator (`template/`): component registry, answers
  schema, prune + rename + doc-regeneration pipeline, structural verifier and
  a six-configuration combo matrix.
- fastlane surface — nine lanes (`bootstrap_asc`, `beta`, `screenshots`,
  `metadata`, `release`, `certs`, `status`, `mac_beta`, `notarize`) with
  App Store Connect API-key auth.
- CI posture: Linux gates on every push, dispatchable `macos-26` compile
  matrix as the release gate.
- Agent surface: `.claude/` (7 subagents, 11 commands, 5 rule files, 10
  hooks), `.mcp.json` with three servers and zero secrets, `VIBE.yaml`
  policy, and the skeleton gate scripts under `scripts/`.
- Nine ADRs recording the design decisions in `docs/adr/`.
