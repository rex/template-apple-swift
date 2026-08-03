# MAP

<!-- Where things live and what breaks what. TEMPLATE MODE: this file describes
     the MACHINERY. template/generate.py replaces it at onboarding with a map of
     the generated app (from template/docs/fragments/map/). Keep under 150 lines. -->

The app code is documented by `AGENTS.md` §4 and the per-target `AGENTS.md`
files. This file is about the **machinery** — the parts that exist only because
this is a template, and the coupling between them.

## Where the machinery lives

| Area | Path | Owns |
|---|---|---|
| Generator | `template/generate.py` + `template/tmpl/*.py` | the one-shot transform: prune → rename → docs → VIBE → settings → finalize |
| Component registry | `template/components.yaml` | which files/dirs/markers/includes each component owns; the single source of truth for pruning |
| Answers contract | `template/answers.schema.json`, `answers.example.yaml` | the onboarding question set; unknown keys are errors |
| Combo matrix | `template/ci-combos/*.yaml` | six pinned answer sets CI generates + verifies |
| Doc fragments | `template/docs/fragments/<doc>/NN-<key>.md` | the generated repo's AGENTS/MAP/README/TASK_STATE/PROGRESS |
| Structural verifier | `template/verify.py` | asserts a generated tree is coherent (no orphan markers, bundle-ID shapes, App Group count) |
| Project spec | `project.yml` + `xcodegen/components/*.yml` | all ten targets; components merge in via `include:` |
| Build settings | `Config/Shared.xcconfig`, `Config/Versions.xcconfig` | the only files allowed to name `DEVELOPMENT_TEAM` / versions |
| Release | `fastlane/`, `ExportOptions.plist`, `Gemfile.lock` | the nine lanes; `template/payload/release.yml` is installed only for `github_actions` |
| CI | `.github/workflows/ci.yml` (Linux, every push), `verify-macos.yml` (dispatch) | structural gates vs. compile truth |
| Agent surface | `.claude/`, `.mcp.json`, `VIBE.yaml`, `scripts/*.py` | hooks, agents, commands, rules, policy, gates |

## What breaks what

Read this before changing anything in the left column.

| If you change… | You must also… | Or this breaks |
|---|---|---|
| a component's files or dirs | update `owns:` in `template/components.yaml` | pruning leaves orphans; `verify.py` fails the combo matrix |
| a `// @template:<id>` block | keep BEGIN/END whole-line and un-nested; keep the file in `marker_files:` | `prune.py` strips the wrong span or `verify.py` reports an orphan marker |
| `xcodegen/components/*.yml` | add/keep its entry in `components.yaml` `includes:` **and** in `project.yml` `include:` | the component's targets vanish, or xcodegen fails on a fragment naming a pruned target |
| a target's bundle ID | keep extension IDs = host ID + exactly one segment | ITMS-90347 at upload; `verify.py` catches it first |
| the App Group string | keep it exactly 8× across the xcodegen YAML | `verify.py` fails; widgets read an empty suite at runtime |
| `MyApp` / `com.example.myapp` anywhere | remember these are TOKENS the rename engine rewrites longest-first | residual-token lint fails, or a partial rename produces a non-compiling tree |
| `.claude/settings.json` | keep every referenced hook present and executable | the hook silently fails on every session |
| `.claude/hooks/*.sh` copied from the skeleton | keep them byte-identical | `make sync-skeleton` reports drift forever |
| `VIBE.yaml` keys | keep the paths `template/tmpl/vibe.py` edits | onboarding leaves stale policy values |
| doc fragment content | respect the budgets in `template/tmpl/context.py` | generation hard-fails on an over-budget doc |
| `Config/*.xcconfig` keys | never restate them in `project.yml` | the xcconfig is the lowest precedence layer and is silently overridden |

## Extension points

- **New component**: registry entry → `xcodegen/components/<id>.yml` → source
  dir → doc fragment(s) → a combo that exercises it. Walkthrough:
  `docs/template-guide.md` § How to add a component.
- **New generator stage**: a module under `template/tmpl/` with `run(ctx)`,
  wired into `generate.py`'s pipeline; record every mutation on `ctx.plan` or
  the combo tests will catch you lying.
- **New gate**: a `scripts/*.py` PEP-723 script + a Make target + a line in
  `ci.yml` between the `# >>> template-ci` / `# <<< template-ci` markers.

## Where bodies are buried

- **Included specs concatenate arrays with no deduplication.** Exactly one
  file may own a given dependency edge or scheme entry. The root spec must not
  restate what a component contributes.
- **Junction fragments.** `account-mac.yml` exists because keys that need both
  `account` and `mac` cannot live in either single-component file — a fragment
  naming `targets.MyAppMac` would break xcodegen when `mac` is pruned.
- **Skeleton retires `pre-compact.sh`; ours is `pre-compact-apple.sh`** so `make sync-skeleton --apply` can never delete it.
  `make sync-skeleton --apply` deletes it even though `settings.json` wires it.
- **`make sync-skeleton --apply` re-adds `serena-required.sh`,
  `serena-gate.sh` and `rules/serena.md`**, all of which ADR-0005 removed.
  They arrive unwired and inert; delete them again.
- **The macOS app has no menu-bar surface in v1** — `MenuBarExtra` has an
  unfixed `setImage:` recursion on macOS 26 (ADR-0009).
- **Watch "mirroring" is a demonstration, not a sync engine.** Each side runs
  its own store; the phone pushes context, the watch displays it.

## Do not edit without an ADR

- `template/components.yaml` component **IDs** — markers, docs and the ASC
  bootstrap all key on them.
- The generator CLI surface (`--answers` / `--dest` / `--apply` / `--dry-run`).
- Scheme names `MyApp`, `MyAppScreenshots`, `MyAppMac`, `MyAppWatch` — the
  Snapfile and every Make target address them by name.
- Fastlane lane names — `make` targets delegate 1:1.

## Quick tour (read order)

1. `README.md` — what this is and how to stamp a repo from it.
2. `AGENTS.md` — the agent contract for this repo.
3. `docs/template-guide.md` — the machinery, in depth.
4. This file — where things live and what couples to what.
5. `docs/adr/README.md` — why the design is the way it is.
