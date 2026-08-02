## Layout

- `{{app_name}}/` — iOS app · `Shared/` — cross-platform models, store, sync, theme
- `Tests/`, `UITests/` — Swift Testing units and the snapshot driver
- `project.yml`, `xcodegen/components/` — the project definition
- `Config/` — `Shared.xcconfig` (team), `Versions.xcconfig` (CI-written)
- `fastlane/` — release lanes · `docs/adr/` — architecture decisions

## Before your first build

1. Drop a 1024×1024 icon into `{{app_name}}/Assets.xcassets/AppIcon.appiconset/`.
2. Create the App Store Connect app record and the `{{app_group}}` App Group
   identifier — neither has an API endpoint (`docs/asc-setup.md`).
3. Confirm `DEVELOPMENT_TEAM = {{team_id}}` in `Config/Shared.xcconfig`.

## Agents

`AGENTS.md` is the contract, `MAP.md` is the module map, `TASK_STATE.md` is the
current slice. `CLAUDE.md` and `GEMINI.md` mirror `AGENTS.md`.
