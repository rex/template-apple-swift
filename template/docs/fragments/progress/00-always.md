# PROGRESS

<!-- ≤50 lines. Read this first in a fresh agent session; TASK_STATE.md has
     the detail. Generated {{date}}. -->

- **Project**: {{display_name}} (`{{bundle_root}}`) — Swift 6 / SwiftUI
- **Components**: {{enabled_list}}
- **Active TASK_STATE**: `TASK_STATE.md` (slice S1, not started)
- **Last session**: {{date}} (generated from template-apple-swift)

## Last three decisions

- {{date}} Generated from `template-apple-swift`; see `docs/onboarding-record.md`
- {{date}} Persistence, targets and capabilities fixed at onboarding
- {{date}} Xcode project is a build artifact — `project.yml` is the source

## Open blockers

- App Store Connect record + App Group identifier must be created by hand

## How to resume

1. Read `AGENTS.md`, then `TASK_STATE.md`.
2. `make bootstrap && make lint test build` — confirm green before editing.
3. Check `MAP.md` for the module you are about to touch.

## Do NOT

- Commit `{{app_name}}.xcodeproj`, generated plists, or signing material
- Add CocoaPods or Carthage — SPM only, declared in `project.yml`
