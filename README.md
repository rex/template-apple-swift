# template-apple-swift

A **superset Apple app plus a generator that prunes it**. Instead of stitching
a new project together target by target, you stamp this repo, answer a dozen
questions, and get a coherent iOS (+ macOS + watchOS + extensions) app that
already builds, tests, lints, signs and ships.

Everything is on in the template so the superset always compiles. Onboarding
deletes what you did not pick.

- **Targets**: iOS app, macOS app, watchOS app, home widgets, Mac widget, Live
  Activity, Watch complications, Notification Service Extension, unit tests, UI
  tests (which double as the fastlane screenshot driver).
- **Stack**: Swift 6 language mode, SwiftUI, `@Observable`, SwiftData,
  Swift Testing, App Intents, String Catalogs, Privacy Manifests, StoreKit 2,
  Sign in with Apple, MetricKit.
- **Machinery**: XcodeGen (`project.yml` is the source of truth), fastlane
  (nine lanes), a Linux CI gate plus a dispatchable macOS compile matrix, and a
  full agent surface (`.claude/`, `.mcp.json`, `VIBE.yaml`, gate scripts).
- **Floors**: iOS 18.0 · macOS 15.0 · watchOS 11.0 — one OS cohort by
  construction. Built with Xcode 26.6; XcodeGen ≥ 2.46.0.

## Requirements

| | |
|---|---|
| macOS | for anything that compiles, tests, signs or ships |
| Xcode | 26.x (26.6 pinned) — App Store submission has required Xcode 26 since 2026‑04‑28 |
| XcodeGen | ≥ 2.46.0 (`brew install xcodegen`) |
| Ruby | 3.4.x + `bundle install` (fastlane 2.237.0, pinned in `Gemfile.lock`) |
| uv | for the generator and the gate scripts (PEP‑723 scripts, no venv to manage) |
| Claude Code | **≥ 2.1.144** — below that, custom spinner verbs leak into the past‑tense turn‑completion message. `session-start-apple.sh` warns, never blocks. |

Linux and cloud sessions are fully supported for everything that is not a
compile: the generator, its test suite, the structural verifier and the
lint/architecture/version gates all run there via `make ci-linux`.

## Stamping a new app

Two paths. Both end at `/onboard`.

### 1. GitHub "Use this template" (recommended)

Click **Use this template → Create a new repository** on the GitHub page, then:

```bash
git clone git@github.com:<you>/<your-app>.git && cd <your-app>
claude          # accept the workspace-trust dialog on first run
/onboard
```

You get a clean history with no upstream remote, which is what you want for an
app that will diverge immediately.

### 2. Plain clone

```bash
git clone https://github.com/piercemoore/template-apple-swift.git MyNewApp
cd MyNewApp
rm -rf .git && git init          # drop the template's history
claude
/onboard
```

Prefer to keep the template repo pristine? Generate into a sibling directory
instead of transforming in place:

```bash
cp template/answers.example.yaml template/answers.local.yaml   # then edit
uv run template/generate.py --answers template/answers.local.yaml --dest ../MyNewApp
```

## What `/onboard` does

It asks for identity (app name, display name, bundle root, team ID), which
components you want, deployment floors and ops preferences; writes
`template/answers.local.yaml`; shows you a dry-run plan; and then runs the
one-shot generator. That prunes disabled components, rewrites every identity
token longest-first, regenerates the orientation docs, retunes `VIBE.yaml`,
materializes the spinner corpus, and deletes `template/` itself.

The generator runs **no git commands**. Commit or stash before `--apply`; that
is your only way back. It is deliberately not re-runnable — post-onboarding
component changes are ordinary engineering, guided by
[`docs/template-guide.md`](docs/template-guide.md).

## First run after onboarding

1. `make bootstrap` — writes `Config/Versions.xcconfig` and runs `xcodegen`.
2. **Drop a 1024×1024 master icon** into your app's `Assets.xcassets/AppIcon`
   well (and the Mac/Watch wells if you kept those targets). The template ships
   empty icon sets on purpose — a placeholder icon that reaches TestFlight is
   worse than a loud failure — and the fastlane `beta` lane preflights this.
3. Put your real Team ID in `Config/Shared.xcconfig` if you used the
   placeholder. It is the only file allowed to name `DEVELOPMENT_TEAM`.
4. `make build && make test`.
5. Run `claude` once interactively and accept workspace trust, so the three
   `.mcp.json` servers leave "pending approval" and `headersHelper` can run.

## Verifying the template itself

```bash
make ci-linux        # everything that does not need Xcode
make verify          # the full gate chain (macOS)
```

Compile truth lives in **`.github/workflows/verify-macos.yml`**, a
`workflow_dispatch`-only matrix: six pinned answer combinations (superset,
minimal, ios-widgets-la, ios-watch, universal, no-health) each generated, then
`xcodegen` + `xcodebuild build` + tests on a `macos-26` runner. macOS runner
minutes bill ~10× Linux, so it is on demand rather than on every push. **A
green matrix is the release gate** — always run it before tagging a template
version.

```bash
gh workflow run verify-macos.yml
```

## Layout

See [`AGENTS.md`](AGENTS.md) §4 for the tree, [`MAP.md`](MAP.md) for what
couples to what, and [`docs/adr/`](docs/adr/) for why.

## License

MIT — see [`LICENSE`](LICENSE).
