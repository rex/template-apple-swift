# Tasks — <feature-slug>

> Concrete task list derived from `plan.md`. Each task maps 1:1 to a slice.
> Implementers execute from this file; planners write into it. `TASK_STATE.md`
> at the repo root tracks the ACTIVE slice and the handoff note; this file is
> the full catalog for the feature.

## How to use this file

- Check off tasks as they complete.
- Add `(agent: <name>)` when an agent picks one up.
- Add `(blocked: <reason>)` when one blocks.
- Acceptance criteria are EARS-notation copies from `spec.md`.
- Test IDs are Swift Testing node ids — the string you can hand to
  `xcodebuild -only-testing:`, e.g.
  `MyAppTests/CheckpointStoreTests/logCheckpointUpdatesTodayCount()`.

## Phase 1 — Contracts & project structure

### S1.1 — Frozen types

- **Files**: `Shared/<area>/<File>.swift` (new)
- **Files (do NOT edit)**: (none — new file)
- **Acceptance**:
  - [ ] Every new type declares `@MainActor` or `nonisolated` explicitly.
  - [ ] The types compile with no call sites yet.
  - [ ] Tests: `MyAppTests/<Suite>/<testName>()`
  - [ ] `make lint` green
- [ ] Complete

### S1.2 — Project structure

- **Files**: `project.yml`, `xcodegen/components/<id>.yml`,
  `template/components.yaml`
- **Acceptance**:
  - [ ] `make regenerate` succeeds and the new files land in the intended
        targets (check target membership, not just the file list).
  - [ ] Any new `include:` entry uses the object form with
        `relativePaths: false`.
  - [ ] No dependency edge, source entry or scheme entry is declared twice —
        included arrays concatenate without deduplication.
  - [ ] `uv run template/verify.py` green
- [ ] Complete

### S1.3 — Entitlements + privacy

- **Files**: the owning `xcodegen/components/<id>.yml`,
  `<Target>/PrivacyInfo.xcprivacy`
- **Acceptance**:
  - [ ] New entitlement / Info.plist keys ride the component fragment, so
        pruning the component removes them.
  - [ ] Every required-reason API used is declared in the privacy manifest.
  - [ ] Extension bundle IDs are still host ID + exactly one segment.
  - [ ] `make regenerate && make build` green
- [ ] Complete

## Phase 2 — Behavior

### S2.1 — Store + persistence

- **Files**: `Shared/Store/<File>.swift`,
  `Tests/MyAppTests/<File>Tests.swift` (new)
- **Acceptance**:
  - [ ] When `<operation>` is called, the store shall <observable result>.
  - [ ] If <error condition>, then the store shall <recovery behavior>.
  - [ ] Tests: `MyAppTests/<Suite>/<happyPath>()`,
        `MyAppTests/<Suite>/<errorPath>()`
  - [ ] `make test` green
- [ ] Complete

### S2.2 — Cross-process payload

- **Files**: `Shared/Sync/WidgetSync.swift` (extend), extension readers
- **Files (do NOT edit)**: the frozen contracts from S1.1
- **Acceptance**:
  - [ ] Hosts write the new field on every mutation; extensions only read.
  - [ ] An extension reading an older payload shall degrade, not crash.
  - [ ] Tests: `MyAppTests/WidgetSyncTests/<roundTrip>()`
- [ ] Complete

### S2.3 — Views

- **Files**: `MyApp/Views/<File>.swift`
- **Acceptance**:
  - [ ] The view reads from the store and mutates only through it.
  - [ ] No hex literal, magic number or ad-hoc font — `Theme` tokens only.
  - [ ] No string literal in a user-facing position.
- [ ] Complete

## Phase 3 — Surfaces

### S3.1 — Widgets / complications

- **Acceptance**:
  - [ ] Every widget view calls `.containerBackground(_:for: .widget)`.
  - [ ] `supportedFamilies` contains no family unavailable on that platform.
  - [ ] The `TimelineProvider` conformance is `nonisolated`.
  - [ ] Verified visually in the widget gallery, not just compiled.
- [ ] Complete

### S3.2 — Live Activity

- **Acceptance**:
  - [ ] `ContentState` changes are mirrored by the writer in the same commit.
  - [ ] Guarded with `#if os(iOS)`, not `#if canImport(ActivityKit)`.
  - [ ] Lock Screen and Dynamic Island presentations both checked.
- [ ] Complete

### S3.3 — App Intents

- **Acceptance**:
  - [ ] Metadata uses `static let`; `perform()` is `@MainActor`.
  - [ ] Every `AppShortcut` phrase contains `\(.applicationName)`.
  - [ ] The intent routes through the store, not a private code path.
  - [ ] Verified in Shortcuts.app.
- [ ] Complete

## Phase 4 — Polish & release readiness

### S4.1 — Localization

- **Acceptance**:
  - [ ] Every user-facing string has a String Catalog entry with a comment.
- [ ] Complete

### S4.2 — Accessibility

- **Acceptance**:
  - [ ] Every interactive element has a label; Dynamic Type at XXL does not
        clip; VoiceOver order is sane.
- [ ] Complete

### S4.3 — Release readiness

- **Acceptance**:
  - [ ] `make archive` clean.
  - [ ] Screenshots refreshed (`make screenshots`) if UI changed.
- [ ] Complete

## Done when

- [ ] All phase tasks checked.
- [ ] `make check-if-the-agent-can-consider-this-task-completed` green.
- [ ] `make test` and `make ui-test` green on a Mac.
- [ ] No open blockers in `TASK_STATE.md`.
- [ ] ADR written if a frozen decision or architecture changed.
- [ ] `CHANGELOG.md` entry + version bump.
