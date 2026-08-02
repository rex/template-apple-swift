## Decisions made this task

- <date> <decision> (ADR link if the decision is architectural)

## Blockers

- (none)

## Handoff note

<What the next session needs to know that is not obvious from the diff.>

## Do NOT

- Hand-edit `{{app_name}}.xcodeproj`, any `Info.plist`, or any `.entitlements`
  — all three are generated. Edit `project.yml` and run `make regenerate`.
- Put `DEVELOPMENT_TEAM`, `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`
  anywhere but `Config/*.xcconfig`.
