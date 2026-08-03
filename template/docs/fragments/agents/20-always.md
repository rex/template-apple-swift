## 4. Repo layout

```
{{app_name}}/                    iOS app target — Views/, Services/, Intents/
Shared/                     cross-platform: Models/, Store/, Sync/, Theme/, Env/
  Store/CheckpointStore.swift  the ONLY mutation path; writes WidgetSync
  Sync/WidgetSync.swift        App Group bridge (hosts write, extensions read)
Tests/{{app_name}}Tests/         Swift Testing unit tests
UITests/{{app_name}}UITests/     UI tests + the fastlane snapshot driver
Config/                     Shared.xcconfig (team) · Versions.xcconfig (CI-written)
xcodegen/components/        per-component spec fragments merged via `include:`
project.yml                 XcodeGen manifest — source of truth for all targets
```
