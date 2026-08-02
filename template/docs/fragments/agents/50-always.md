## 8. Architectural decisions

`docs/adr/` — read `0001` (superset/prune assembly) and `0006` (xcodegen-native
composition) before touching `project.yml` or `xcodegen/components/*.yml`.
Arrays in included specs CONCATENATE with no deduplication: exactly one file may
own any given dependency edge, source entry or scheme entry.

## 9. Things agents get wrong here

- Editing `Info.plist` / `.entitlements` on disk — they are generated; edit the
  `info:` / `entitlements:` blocks in YAML instead.
- Hand-editing the `.xcodeproj` instead of running `make regenerate`.
- Dropping `relativePaths: false` from an `include:` entry, which re-roots every
  path in the included file and breaks the whole spec.
- Adding `options.bundleIdPrefix`. Every target declares an explicit
  `PRODUCT_BUNDLE_IDENTIFIER`; a missing one must fail loudly.

## 10. Workflow

1. Read this file. 2. Read `MAP.md` for the module you are touching.
3. Read the nearest subdirectory `AGENTS.md`. 4. Run §3 before declaring done.
5. Update `TASK_STATE.md` + `PROGRESS.md` when the session ends.

## 11. Subdirectory AGENTS.md (nearest wins)
