## Quick start

```bash
make bootstrap        # Config/Versions.xcconfig + package resolution
make regenerate       # XcodeGen -> {{app_name}}.xcodeproj (a build artifact)
make build test       # build the iOS app, run the unit tests
open {{app_name}}.xcodeproj
```

Requires Xcode 26.x and XcodeGen ≥ 2.46.0 (`brew install xcodegen`).

## Targets

{{targets_table}}

## Components

{{components_table}}
