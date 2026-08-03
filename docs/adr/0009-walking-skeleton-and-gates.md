# ADR 0009 — "Checkpoints" walking skeleton, MyApp identity, gate scope,
#            one-shot onboarding

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner), Fable
- **Scope:** The generic app's domain and identity; architecture-gate scope
  (C8); /api/health applicability (C9); UI-test target (C10); onboarding
  lifecycle

## Context

The superset app needs a domain that exercises every cross-target seam
Pennywise proved (timer-ish live state, cross-process sync, push-driven widget
refresh, watch mirroring) while containing zero transplantable business logic.
Placeholder identity must compile, match the lang-swift-apple templates, and
survive mechanical rename. Several universal-contract questions need explicit
answers rather than silent gaps.

## Decision

1. **Domain: "Checkpoints"** — a session you start/stop and checkpoints logged
   while it runs. `CheckpointStore` (@Observable, @MainActor) is the single
   mutation path; every surface (views, widgets, Live Activity, complications,
   watch, Mac menu bar, App Intents, NSE mirror) renders from it. Contracts:
   construction `contracts.md` §4 (in git history; `specs/_build/` was
   deleted at end of construction) → regenerated docs (shipped).
2. **Identity: `MyApp` / `com.example.myapp`** (lang-swift-apple template
   values; valid identifiers; longest-first rename with residual-token lint).
3. **Architecture gate scope (C8):** NO `scope_globs` (opt-out default scans
   everything — immune to the missed-directory failure and to renames);
   `exclude_globs` = binary assets (xcassets, images, fonts, caf, icns),
   `**/Generated/**`, `*.xcstrings`, `*.xcodeproj/**`. Limits: soft 250 / hard
   400 (skeleton standard).
4. **/api/health (C9):** not applicable to native Apple clients — recorded here
   and in `VIBE.yaml::project.decisions[]`; the health surface is MetricKit +
   BuildInfo diagnostics.
5. **UI tests (C10):** `MyAppUITests` (bundle.ui-testing) is always-on, serves
   `make ui-test` AND doubles as the fastlane `snapshot` driver via a
   screenshot scheme.
6. **One-shot onboarding:** the generator refuses to run twice (`template/`
   self-destructs at finalize). Post-onboard component changes are ordinary
   engineering guided by `docs/template-guide.md`; re-runnable toggling is
   explicitly out of v1 scope.

## Consequences

- All construction-time Swift must satisfy the 400-line hard cap from birth.
- The Checkpoints domain ships as genuinely useful example code agents will
  read as canon — it must exemplify the north star (Swift 6 strict concurrency,
  @Observable, Theme tokens, String Catalogs, Swift Testing).
- HealthKit module is iOS-only in v1 (watch workout support deferred).
- Pennywise is a Swift **5.10** codebase on every target. It is the reference
  for API shape, target/entitlement/plist wiring and product behaviour —
  **not** for Swift 6 concurrency. Three of its patterns (WCSession delegate
  hops, `static var` App Intent metadata, unannotated `TimelineProvider`
  structs) are compile errors under our settings. (R4 V1)
- **The Mac app has NO menu-bar surface in v1** (R2: Pennywise's macOS-26
  MenuBarExtra `setImage:` recursion has no public trace/fix; rather than ship
  either the risky SwiftUI API or the AppKit workaround as canon, v1 ships a
  main-window Mac app only). `docs/template-guide.md` carries the hazard note
  pointing at Pennywise's manual-`NSStatusItem` pattern for apps that need one.
