# AGENTS.md

<!-- Single source of truth for Claude Code, Codex, Gemini CLI, Cursor, Copilot.
     CLAUDE.md and GEMINI.md are symlinks to this file. Keep under 150 lines.
     TEMPLATE MODE: template/generate.py REPLACES this file at onboarding from
     template/docs/fragments/agents/. Edit fragments, not this file, if you want
     a change to survive into generated repos. -->

> ## ⚠ THIS IS AN UN-ONBOARDED TEMPLATE
>
> This repo is `template-apple-swift` itself, not an app. Every identity token
> is a placeholder (`MyApp` · `com.example.myapp` · `ABCDE12345`) and every
> optional component is switched on so the superset always compiles.
>
> **In an un-onboarded tree there is exactly one job: `/onboard`.** It collects
> identity + components, runs the one-shot generator, prunes what you did not
> pick, renames everything, and deletes `template/`.
>
> Do not start feature work here. Do not "fix" the placeholder names. If you
> are here to improve the machinery itself, read `docs/template-guide.md`
> first — it explains markers, the component registry, and what breaks what.

## 1. Project snapshot

- **What**: a superset Apple app (iOS + macOS + watchOS + five extensions)
  plus the generator that prunes it down to the app someone actually wants.
- **Runtime**: Swift 6 (language mode `6.0`), SwiftUI, `@Observable`,
  SwiftData. Floors iOS 18.0 · macOS 15.0 · watchOS 11.0. Build SDK is the
  latest stable Xcode (26.6); XcodeGen ≥ 2.46.0.
- **Machinery**: `template/` (generator + registry + combo matrix),
  `xcodegen/components/` (per-component spec fragments), `fastlane/`,
  `.github/workflows/`, `.claude/`.
- **Owner**: @pierce.
- **Non-goals**: this repo is not an app and never ships to the App Store.
  The generator is one-shot and deliberately not re-runnable.

## 2. Setup

```bash
make help             # every target, grouped
make ci-linux         # the Linux-runnable gate chain (no Xcode needed)
make verify           # full gate chain — macOS only
```

`/onboard` is the entry point for using the template. Everything else here is
maintenance of the template itself.

## 3. Commands the agent MUST run before declaring done

```bash
make lint             # formatters + shellcheck + architecture + version gates
make ci-linux         # structure checks + template pytest suite
make test             # xcodebuild — macOS only; say so plainly if you skipped it
```

If `xcodebuild` is not on this machine, `make ci-linux` is the gate you ran and
the compile gates did **not** run. Never report a build result you did not see.

## 4. Repo layout

```
MyApp/                  iOS app target — Views/, Services/, Intents/
MyAppMac/ MyAppWatch/   macOS + watchOS app targets
HomeWidget/ MacWidget/ LiveActivity/ WatchComplications/ NotificationService/
Shared/                 cross-platform: Models/, Store/, Sync/, Theme/, Env/
Tests/ UITests/         Swift Testing units + XCUITest / snapshot driver
Config/                 Shared.xcconfig (team) · Versions.xcconfig (CI-written)
xcodegen/components/    per-component spec fragments merged via `include:`
project.yml             XcodeGen manifest — source of truth for all targets
template/               THE GENERATOR — deleted at onboarding
docs/template-guide.md  how the machinery works; read before changing it
specs/_template/        spec/design/plan/tasks starters for new work
```

## 5. Code style

`.claude/rules/swift.md` is the hard-stop list; `CONVENTIONS.md` is the longer
digest. Headline: explicit `@MainActor`/`nonisolated` on every type, `Theme`
tokens instead of literals, `@Observable` only, files 250 soft / 400 hard.

## 6. Testing policy

`VIBE.yaml` `quality_gates.tests.mode: required`. Swift Testing (`@Test` /
`#expect`) for units; the template's own generator suite is pytest under
`template/tests/` and runs on Linux.

## 7. Security (hard stops)

- No secrets in source. `.claude/settings.json` denies `Read` on
  `AuthKey_*.p8`, `*.p12`, `*.mobileprovision` and `fastlane/.env*`.
- `DEVELOPMENT_TEAM` lives only in `Config/Shared.xcconfig`; an `.xcconfig` is
  the lowest precedence layer, so the same key in `project.yml` silently wins.
- MCP credentials never touch `.env` — they resolve at connect time through
  `scripts/mcp/op-headers.sh` and degrade to OAuth / anonymous tier.
- Full checklist: `.claude/rules/security.md`.

## 8. Architectural decisions

`docs/adr/` — nine accepted ADRs. Read `0001` (superset/prune assembly) and
`0006` (xcodegen-native composition) before touching `project.yml` or any
`xcodegen/components/*.yml`; read `0008` before adding anything to `.claude/`.

## 9. Things agents get wrong here

- Editing `Info.plist` / `.entitlements` on disk — they are generated from
  YAML and gitignored. Edit the `info:` / `entitlements:` blocks instead.
- Hand-editing `MyApp.xcodeproj` instead of running `make regenerate`.
- Adding a component's files without adding it to `template/components.yaml`,
  so the generator cannot prune it and `verify.py` fails.
- Dropping `relativePaths: false` from an `include:` entry, which re-roots
  every path in the included file.
- Treating `MyApp` as a name to fix by hand. It is a token the generator
  rewrites; changing it manually breaks the rename contract.

## 10. Workflow

1. Read this file. 2. Read `docs/template-guide.md` if you are changing the
machinery. 3. Read `MAP.md` for where a thing lives. 4. Read the nearest
subdirectory `AGENTS.md` before editing that subtree. 5. Run §3 before
declaring done. 6. Update `TASK_STATE.md` + `PROGRESS.md` when the session ends.

## 11. Composition with skills

Bootstrapped from `agentic-skeleton` (collaboration container, gates, VIBE
schema) + `lang-swift-apple` (Swift 6 / Apple patterns). Durable new rules go
in the right **skill**, not in this file. Transient context goes in
`TASK_STATE.md`, never here.

## 12. Subdirectory AGENTS.md (precedence: nearest wins)

- `MyApp/AGENTS.md` — iOS app target
- `MyAppMac/AGENTS.md` — macOS app target
- `MyAppWatch/AGENTS.md` — watchOS companion
- `Shared/AGENTS.md` — cross-platform code, the store, and the sync seams

**Extension directories carry none, by design.** `HomeWidget/`, `MacWidget/`,
`LiveActivity/`, `WatchComplications/` and `NotificationService/` are small,
single-purpose, and their rules are the gotcha table in
`.claude/rules/swift.md`. A per-extension AGENTS.md would be five copies of
the same four lines and five more files to keep honest.
