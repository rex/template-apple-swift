---
description: Turn this template into a real app — identity, components, then the one-shot generator.
argument-hint: (optional) app name in PascalCase, e.g. Ledger
disable-model-invocation: true
allowed-tools: AskUserQuestion, Read, Write, Edit, Bash(uv run:*), Bash(make:*), Bash(git:*), Glob, Grep
---

Onboard this repo into a real app$ARGUMENTS.

> **This is one-shot and destructive.** `--apply` deletes targets, rewrites
> every identity token in every file, strips marker blocks, and removes
> `template/` — including the generator that did it. There is no
> `--undo`, the generator runs **no git commands**, and it is deliberately
> not re-runnable. `--dry-run` is the only rehearsal you get.
>
> Say that to the user in your own words before anything is written, and do
> not run `--apply` without an explicit yes.

## 0. Refuse early if this is not a template

- `template/` present: !`test -d template && echo yes || echo NO`

If that says `NO`, this repo has already been onboarded. **Stop.** Point the
user at `docs/template-guide.md` §8 for adding a component after the fact, and
at `.claude/rules/swift.md` for the rules that outlived the generator.

## 1. Load the ground truth

Read, in this order, before asking anything:

1. `template/answers.example.yaml` — every field, its default, and why.
2. `template/components.yaml` — the frozen component IDs and their `requires:`
   edges. `complications` requires `watch`; `widget-mac` requires `mac`.
3. `template/ci-combos/` — six worked answer files. If the user's shape matches
   one (`ios-widgets-la`, `ios-watch`, `universal`, `minimal`, `no-health`,
   `superset`), read it and offer it as a starting point instead of walking the
   whole questionnaire.

Never invent a field name. Unknown keys are generator ERRORS, not warnings —
a typo'd component must never be read as "off".

## 2. Identity — conversational, not a form

Ask for these in prose, one exchange, and echo back what you understood:

| Field | Rules |
|---|---|
| `app_name` | PascalCase, a valid Swift identifier, 2–30 chars. Becomes the target names (`<Name>`, `<Name>Mac`, `<Name>Watch`, `<Name>Tests`, `<Name>UITests`), the source directories, and the scheme names. |
| `display_name` | Human-facing, ≤30 chars, spaces allowed. Defaults to `app_name`. |
| `bundle_root` | The iOS **and** macOS bundle ID — one string. Universal Purchase requires both platforms to share it. Every extension ID is this plus exactly one segment. |
| `team_id` | The 10-character Apple Developer Team ID. Goes to `Config/Shared.xcconfig` and nowhere else. |

Then one more question that is not a schema field but changes the ending:
**does an App Store Connect app record already exist for that bundle ID?**
If no, §7's handoff is mandatory reading rather than a footnote.

If the user does not have a Team ID yet, take the `ABCDE12345` placeholder and
tell them plainly that `make testflight` will fail until they replace it.

## 3. Batch A — platforms (AskUserQuestion)

Ask these together:

1. **macOS app?** → `components.mac` (default yes; brings Universal Purchase)
2. **watchOS companion?** → `components.watch` (default yes)
3. **Deployment floors** → `default` (iOS 18.0 / macOS 15.0 / watchOS 11.0, one
   OS cohort, ~93% of active iPhones) or `modern` (26.0 / 26.0 / 26.0, only for
   apps that hard-adopt OS-26 design APIs)

The build SDK is always the latest stable Xcode's regardless — the floor is a
minimum, not a target.

## 4. Batch B — extensions (AskUserQuestion)

Offer only what the Batch A answers allow. Ask them together:

1. **Home-screen / Lock Screen widgets?** → `widgets-home`
2. **Live Activity + Dynamic Island?** → `live-activity`
3. **Push notifications with a Notification Service Extension?** → `nse`.
   Say what this actually buys: the host gains the `aps-environment`
   entitlement and APNs registration, and the NSE is what makes a
   `mutable-content: 1` payload reliable, since silent pushes are
   rate-budgeted by iOS and dropped without warning.
4. **Watch complications?** → `complications` — **only if `watch` is on**
5. **macOS widget?** → `widget-mac` — **only if `mac` is on**

Never present a component whose `requires:` are unmet. A dependency violation
is a generator error with the fix printed, and hitting it means this command
asked a bad question.

## 5. Batch C — capabilities (AskUserQuestion)

1. **SwiftData persistence?** → `swiftdata`, default **on**. Off leaves the
   always-on in-memory `CheckpointPersisting` implementation and sets
   `VIBE.yaml persistence: none`.
2. **StoreKit 2 paywall stub?** → `store`, default off.
3. **Sign in with Apple + CloudKit stub?** → `account`, default off. Adds the
   SIWA and iCloud entitlements, and an iCloud container you must create by
   hand in the developer portal.
4. **HealthKit?** → `health`, default **off**, and say why: App Review
   scrutinises health entitlements hard, and an unused HealthKit entitlement is
   a rejection risk for zero benefit.

## 6. Batch D — ops (AskUserQuestion)

1. **CI** → `ci_system`: `xcode_cloud` (default — `ci_scripts/ci_post_clone.sh`
   drives builds, no runner minutes), `github_actions`, or `none`.
2. **Signing** → `signing`: `automatic` (default; Xcode cloud-managed
   distribution certs work for the App Store) or `match` (recommended for
   Developer ID / notarised Mac builds).
3. **Spinner flavour** → `spinner_flavor`, default **true**. Needs Claude Code
   v2.1.144+; below that verbs leak into the past-tense completion line.
4. **Status line** → `statusline`, default **false**, because a project
   `statusLine` replaces a personal one rather than merging with it.
5. **Autonomy** → `autonomy`: `continue-until-blocked` (default) or
   `interactive`. Recorded in `VIBE.yaml`.
6. **Squash history?** → `squash_history`, default **no**. Advisory only — the
   generator runs no git commands; true just adds "squash it yourself" to the
   onboarding record.

`frameit` stays `false` unless the user asks: it needs ImageMagick plus
community device frames, and `make screenshots` should have no surprise
system dependency.

## 7. Write, rehearse, apply

1. Write `template/answers.local.yaml` (gitignored). Keep the example file's
   comments where they still apply. Show the finished file and list every
   default you took on the user's behalf.
2. Tell them to commit or stash first. `--apply` is irreversible.
3. Rehearse:

   ```bash
   uv run template/generate.py --answers template/answers.local.yaml --dry-run
   ```

   Walk the plan with them: deletions, renames, marker strips, include-entry
   removals. Dependency violations are ERRORS with the fix printed — fix the
   answers file and re-run rather than working around them.
4. On an explicit yes:

   ```bash
   uv run template/generate.py --answers template/answers.local.yaml --apply
   ```

   Use `--dest ../<Name>` instead of `--apply` when they want this template
   repo left intact.

## 8. After the transform

1. `make bootstrap` — **macOS only.** It runs `xcodegen` and hard-fails
   without it. On Linux say so plainly, do not fake it, and point at
   `.github/workflows/verify-macos.yml`: that is where the project generates
   and the three schemes compile. `make ci-linux` is the gate you *can* run
   here, and it does not compile a single line of Swift.
2. Confirm `template/` is gone and that a search for the old tokens
   (`MyApp`, `com.example.myapp`, `ABCDE12345`) returns nothing outside
   `docs/`.
3. Commit per repo discipline — a signed commit, conventional message,
   `CHANGELOG.md` entry, and the pre-commit hooks installed by `make
   bootstrap` (or `pre-commit install` by hand). Never `git push --force`;
   `.claude/settings.json` denies it.
4. Read the regenerated `AGENTS.md`. It now describes the real app, and the
   un-onboarded-template banner at the top should be gone.

## 9. App Store Connect handoff

Print this as the closing block, always — it is the part that bites weeks
later:

```bash
make asc-bootstrap     # register every bundle ID + capability via the API
make asc-status        # read back what App Store Connect actually thinks
```

Then the residue Apple gives no API for, all of it in `docs/asc-setup.md`:

- **The app record.** No create-app endpoint exists; `produce` needs an Apple
  ID + 2FA session. Create it in the web UI.
- **The App Group** `group.<bundle_root>` — created by hand in the developer
  portal, and everything cross-process in this app (widgets, complications,
  the NSE) is dead without it.
- **The iCloud container**, only with the `account` component.
- **A 1024×1024 master icon** dropped into the app's `AppIcon` well. The
  `beta` lane preflights it and fails early rather than after a 12-minute
  archive.
- **An API key that is a Team key.** Individual keys cannot touch provisioning
  endpoints or notarytool, and the failure message does not say so.

Close by telling them `/release` is the runbook from here, and
`docs/release-automation.md` is the long form.
