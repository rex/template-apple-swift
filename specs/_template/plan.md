# Plan — <feature-slug>

> Phased implementation plan derived from `spec.md` + `design.md`.
> The planner subagent writes this; the implementer executes it slice by
> slice. `TASK_STATE.md` tracks which slice is active.

## Phases

### Phase 1 — Contracts & project structure (freeze)

**Exit criteria**: types compile with no call sites; `make regenerate` is
clean; the scheme list is unchanged or intentionally changed.

Slices:
- [ ] S1.1 — Add the frozen types from `design.md` § Contracts (signatures +
      minimal bodies), each with explicit isolation
- [ ] S1.2 — `project.yml` / `xcodegen/components/*.yml` changes, then
      `make regenerate` and confirm target membership
- [ ] S1.3 — Entitlements, Info.plist keys and `PrivacyInfo.xcprivacy`
      updates on the owning include fragment

### Phase 2 — Behavior

**Exit criteria**: `make test` green; the feature works in the simulator on
every enabled surface.

Slices:
- [ ] S2.1 — Store / persistence changes and their tests
- [ ] S2.2 — `WidgetSync` payload changes + the extensions that read them
- [ ] S2.3 — SwiftUI views wired to the store, using `Theme` tokens only

### Phase 3 — Surfaces

**Exit criteria**: every surface listed in `spec.md` renders correctly; no
widget shows the "adopt containerBackground" placeholder.

Slices:
- [ ] S3.1 — Widget / complication timelines
- [ ] S3.2 — Live Activity `ContentState` + the writer that keeps it in step
- [ ] S3.3 — App Intents / Shortcuts surface

### Phase 4 — Polish & release readiness

**Exit criteria**: localized, accessible, archivable.

Slices:
- [ ] S4.1 — String Catalog entries for every user-facing string
- [ ] S4.2 — Accessibility pass (labels, Dynamic Type, VoiceOver order)
- [ ] S4.3 — `make archive` clean; screenshots refreshed if UI changed

## Slice discipline

- Each slice ≤ 150 LOC diff.
- Each slice independently revertable.
- Each slice has its own test(s), listed in `tasks.md`.
- Each slice ends with a build on at least one real target.
- If a phase exceeds 8 slices, split the phase.

## Verification per slice

```bash
make lint            # SwiftFormat/SwiftLint + architecture + version gates
make build           # iOS app target
make test            # Swift Testing units — macOS only
```

On a machine with no `xcodebuild`, run `make ci-linux` and record in the slice
that the compile gates did not run. Never mark a slice done on an unobserved
build.

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| <risk> | low/med/high | low/med/high | <action> |

## Dependencies

- <API availability above the floors, ASC configuration, design assets> —
  what we need and by when.

## Estimated effort

- Phase 1: <~X slices>
- Phase 2: <...>
- Phase 3: <...>
- Phase 4: <...>

## Frozen decisions (do not re-plan)

Once this document is merged and implementation starts, these are fixed:

- <frozen decision 1>
- <frozen decision 2>

Changing a frozen decision requires an ADR plus a spec and plan update before
implementation continues.
