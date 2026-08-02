# File ownership — implementation waves

> One owner per path per wave. Agents NEVER touch files outside their partition,
> NEVER run git mutations (Fable commits between waves), and code against
> `contracts.md` — never against sibling work-in-progress. Single-owner rule for
> integration files: project.yml (W1A), Makefile (W2C), .claude/settings.json (W2D),
> VIBE.yaml (W2D), Gemfile (W2B).

## Wave 1 — superset Swift app

| Agent | Owns (create/edit) | Explicitly NOT |
|---|---|---|
| W1A structure | `project.yml`, `xcodegen/components/*.yml`, `Config/*.xcconfig`, all `*.entitlements`, all `Info.plist`, all `PrivacyInfo.xcprivacy`, `MyApp/Assets.xcassets/**`, `Shared/Resources/Localizable.xcstrings`, `.gitignore` (append) | any `.swift` |
| W1B shared+tests | `Shared/**/*.swift`, `Tests/**`, `UITests/**` | target dirs, project.yml |
| W1C targets | `MyApp/**/*.swift`, `MyAppMac/**/*.swift`, `MyAppWatch/**/*.swift`, `HomeWidget/*.swift`, `MacWidget/*.swift`, `LiveActivity/*.swift`, `WatchComplications/*.swift`, `NotificationService/*.swift` | `Shared/**`, plists/entitlements (W1A), tests |

Cross-cutting: W1A creates plist/entitlement files that reference W1C's principal
classes by the names in contracts.md §2/§4 (e.g. `$(PRODUCT_MODULE_NAME).NotificationService`).
W1C names types accordingly. Disputes resolve to contracts.md.

## Wave 2 — machinery

| Agent | Owns | Explicitly NOT |
|---|---|---|
| W2A generator | `template/**` (generate.py, tmpl/*.py, components.yaml FINAL, answers.example.yaml, answers.schema.json FINAL, ci-combos/*.yaml, docs/fragments/**, tests/**) | Swift, workflows |
| W2B fastlane | `fastlane/**`, `Gemfile`, `Gemfile.lock`, `.ruby-version`, `ExportOptions.plist`, `template/payload/release.yml`, `docs/release-automation.md`, `docs/asc-setup.md`, `.env.example` | Makefile (targets specified via handoff notes to W2C in `specs/_build/handoff-w2b.md`) |
| W2C build/CI | `Makefile`, `.githooks/**`, `ci_scripts/**`, `scripts/apple/**`, `.github/workflows/ci.yml`, `.github/workflows/verify-macos.yml`, `.pre-commit-config.yaml` | fastlane/, template/, .claude/ |
| W2D agentic | `.claude/**` (except skills/release-ops + statusline + spinner corpus = W2E), `.mcp.json`, `VIBE.yaml`, root `AGENTS.md`/`MAP.md`/`README.md`/`CONVENTIONS.md`/`PROGRESS.md`/`TASK_STATE.md` (post-groundwork rewrite), `CHANGELOG.md`, per-target `AGENTS.md` + `README.md` (all .md — disjoint from W1C .swift), `specs/_template/**`, `docs/template-guide.md`, `.codex/**`, `.gemini/**`, skeleton `scripts/*.py` copies | hooks/commands they don't own? No — W2D owns all .claude except W2E's enumerated files |
| W2E fun layer | `.claude/skills/release-ops/**`, `.claude/statusline.sh`, spinner corpus file + its settings fragment (delivered as `specs/_build/handoff-w2e-settings.json` for W2D to merge — settings.json single-owner = W2D), `.claude/commands/{release,grade-north-star}.md`, `.claude/agents/{apple-reviewer,xcode-build-debugger}.md` | settings.json direct edits |

Wave-2 agents read Wave-1 output freely (committed by then) but only W2A may
depend on its exact content (manifest enumerates real files).
