# Template guide

How the machinery works, how to change it safely, and the hazards that will
bite you if you don't know about them. Read this before touching `template/`,
`project.yml`, `xcodegen/components/`, or anything under `.claude/`.

If you just want to *use* the template, you want `README.md` and `/onboard`.

---

## 1. The model in one paragraph

The repo is a **superset**: every optional surface exists and compiles.
Onboarding runs a one-shot generator that **removes** what you did not pick,
rewrites identity tokens, regenerates the orientation docs, and deletes itself.
Subtraction is the whole design — a generator that adds files has to keep every
combination working in the abstract, while a generator that removes them only
has to keep the superset working, which CI can actually prove.

---

## 2. Identity tokens

Six tokens carry through the whole tree:

| Token | Template value | What it becomes |
|---|---|---|
| App name | `MyApp` | target names, type prefixes, directory names |
| Bundle root | `com.example.myapp` | iOS **and** macOS bundle ID (identical — Universal Purchase) |
| App Group | `group.com.example.myapp` | 8 entitlements + 1 Swift constant |
| Team | `ABCDE12345` | `Config/Shared.xcconfig` only |
| Display name | `MyApp` | `CFBundleDisplayName` |
| Slug | `myapp` | BGTask IDs and other lowercase identifiers |

Substitution is **longest-first**: `group.com.example.myapp` →
`com.example.myapp` → `MyApp` → `myapp`. Any other order corrupts the longer
strings. Binary files (png, car, ttf) are on a skip-list; `.claude/*.txt` and
`settings.json` are NOT — spinner verbs may legitimately contain `MyApp`.

Everything checked in **compiles with the tokens as-is**. They are valid
identifiers, never `__PLACEHOLDER__` syntax, which is why the superset can be
built and tested before anyone onboards.

---

## 3. Marker conventions

Markers are the escape hatch for the small amount of component-specific code
that cannot be a whole file.

```swift
// @template:live-activity BEGIN
LiveActivityController.shared.sync(snapshot)
// @template:live-activity END
```

Rules, all enforced:

- **Whole-line, exact.** `// @template:<component-id> BEGIN` / `... END`.
- **Swift only.** YAML never carries markers; per-component YAML lives in
  include fragments instead, so pruning YAML is always file-level.
- **No nesting.** Blocks for *different* components may sit adjacent inside
  one closure — that is how `MyAppApp.swift`'s fan-out works, and stripping
  any subset must leave compiling code.
- **Only in files listed in `components.yaml` `marker_files:`** (cap 8).
  Everything else a component owns is a whole file or a whole directory,
  which is always preferred.
- `template/tmpl/prune.py` strips blocks for disabled components;
  `template/verify.py` fails on an orphan marker.

The real marker files today: `MyApp/MyAppApp.swift` (swiftdata, nse,
live-activity, watch), `Shared/Store/CheckpointStore.swift` (swiftdata),
`MyApp/Views/SettingsView.swift` (store, account, health),
`MyAppMac/MacRootView.swift` (store, account).

**Design rule:** if you find yourself wanting a fifth marker file, ask whether
the code belongs in the component's own directory instead. Markers are the
expensive option.

---

## 4. The component registry

`template/components.yaml` is the single source of truth for pruning, docs
generation and the App Store Connect bootstrap. One entry per component:

```yaml
components:
  live-activity:
    requires: []                       # component IDs that must also be on
    owns:
      dirs: [LiveActivity]             # deleted wholesale when disabled
      files:                           # individual files deleted when disabled
        - Shared/SessionActivityAttributes.swift
        - MyApp/Services/LiveActivityController.swift
        - Tests/MyAppTests/ActivityAttributesTests.swift
    marker_files:                      # files with blocks to strip
      - MyApp/MyAppApp.swift
    vibe: { extensions.live_activity: true }   # VIBE.yaml keys when enabled
    asc:                               # for the bootstrap_asc fastlane lane
      bundle_ids: [com.example.myapp.liveactivity]
      capabilities: [APP_GROUPS]
```

Plus an `includes:` map from every xcodegen include file to the components it
requires:

```yaml
includes:
  live-activity.yml: [live-activity]
  account-mac.yml: [account, mac]      # junction — see §5
```

The generator keeps an include entry iff **all** its requires are enabled;
otherwise it deletes the file and removes its two-line entry from
`project.yml`'s `include:` list. `prune.py` does no YAML content surgery of
any kind.

`schema_version: 1` is checked on load. A registry the generator cannot
interpret must never prune silently.

---

## 5. Junction includes

Some keys need **two** components at once. `account` adds Sign in with Apple
entitlements; if `mac` is also on, `MyAppMac` needs them too. Neither
`account.yml` nor `mac.yml` may own that line: a fragment naming
`targets.MyAppMac` breaks xcodegen the moment `mac` is pruned, and a fragment
naming `account` keys breaks when `account` is pruned.

The answer is a third file, `account-mac.yml`, declared as
`account-mac.yml: [account, mac]`. It is included only when both are on.

Generalize the rule: **an include fragment may only name targets and keys that
its own `requires:` list guarantees exist.** Every cross-product needs its own
junction file. Ten include files ship today — seven target-bearing (`mac`,
`watch`, `complications`, `widgets-home`, `widget-mac`, `live-activity`,
`nse`) and three capability/junction fragments (`account`, `health`,
`account-mac`).

Capability components that add *no* target and *no* entitlement keys
(`swiftdata`, `store`) need no include file at all: their source directories
are declared once in the root spec as `{ path: ..., optional: true }` and
pruning them is `rm` plus a marker strip.

---

## 6. How xcodegen merging actually works

This governs every structural decision above, so know it precisely:

- Included specs merge **additively**: dictionaries recurse, **arrays
  concatenate**, scalars are replaced.
- The root spec is merged **on top** of the reduced includes, so root wins
  scalar conflicts and root's array items land *after* the includes'.
- **There is no deduplication.** Exactly one file may contribute any given
  dependency edge, source entry or scheme-target entry. The root must not
  restate anything a component contributes.
- A spec included twice is merged once (path-set guard), so shared fragments
  are safe.
- Per-key override is `:REPLACE` (suffix on the key, any depth). It exists for
  emergencies; v1 uses none.
- Every `include:` entry MUST use the object form with `relativePaths: false`.
  The string form defaults to `true` and re-roots every path in the included
  file at that file's own directory, breaking the entire spec.
- There is **no `options.bundleIdPrefix`**. Every target declares an explicit
  `PRODUCT_BUNDLE_IDENTIFIER`, because a prefix would silently invent
  `com.example.HomeWidget` for a target that forgot one — plausible, wrong,
  and an ITMS-90347 rejection. A missing ID must fail loudly.

---

## 7. The combo matrix

Six pinned answer sets in `template/ci-combos/`, each generated and verified:

| Combo | Shape | Proves |
|---|---|---|
| `superset` | everything on | the committed tree is coherent |
| `minimal` | iOS app only, no persistence | every component is genuinely optional |
| `ios-widgets-la` | iOS + widgets + Live Activity + NSE | the extension-heavy iOS path |
| `ios-watch` | iOS + watch + complications | the `requires:` chain and WCSession seam |
| `universal` | iOS + mac + both widgets | Universal Purchase and the mac junction |
| `no-health` | everything except health | the default real-world shape |

Linux CI (`ci.yml`, every push) generates all six and runs `verify.py` on each.
macOS CI (`verify-macos.yml`, `workflow_dispatch`) additionally runs `xcodegen`
and `xcodebuild build` on each. **A green macOS matrix is the release gate** —
always dispatch it before tagging.

Adding a component means adding it to the combos that should exercise it. A
component no combo turns off is a component nobody has proven is prunable.

---

## 8. How to add a component

1. **Write the code** in its own directory (preferred) or as whole files.
   Reach for a marker block only when the code must live inside an existing
   function body, and keep the block to a few lines.
2. **Register it** in `template/components.yaml`: `requires:`, `owns.dirs`,
   `owns.files`, `marker_files:`, `vibe:`, `asc:`.
3. **Add the spec fragment** `xcodegen/components/<id>.yml` if it brings a
   target or any entitlement/Info.plist key. Add an `includes:` entry and an
   `include:` line in `project.yml` with `relativePaths: false`. Add junction
   files for any cross-product keys (§5).
4. **Add the answers field**: `template/answers.schema.json` and
   `answers.example.yaml`, with a comment saying what it brings and its
   default.
5. **Add doc fragments** under `template/docs/fragments/agents/` (and
   `map/` where relevant) named `NN-<component-id>.md` so generated docs
   describe it only when it is on.
6. **Add it to the combos**: at least one combo with it on and one with it
   off. Prefer extending an existing combo over adding a seventh — macOS
   matrix minutes are the expensive resource.
7. **Verify**: `uv run template/generate.py --answers template/ci-combos/<c>.yaml
   --dest /tmp/c --dry-run`, then for real, then `uv run template/verify.py`
   in the generated tree, then `make ci-linux`, then dispatch `verify-macos`.

Checklist for the reviewer: does pruning it leave compiling code? Does keeping
it leave compiling code? Is any file or key owned by exactly one place?

---

## 9. Maintaining the agent layer

`.claude/` mixes two classes of file (ADR-0008):

- **Skeleton-owned, byte-identical**: `hooks/{session-start,inject-state,
  bash-guard,auto-lint,stop-gate,auto-commit,changelog-append}.sh`, the seven
  `agents/*.md`, ten of the `commands/*.md`, and
  `rules/{security,python,ansible,terraform}.md`. `make sync-skeleton --check`
  compares them. **Do not customize these** — put Apple-specific behavior in a
  net-new file instead, which is why `session-start-apple.sh` and
  `auto-lint-swift.sh` exist as *second* hook entries rather than as edits.
- **Net-new (Orphan)**: `hooks/{session-start-apple,auto-lint-swift,
  pre-compact-apple}.sh`, `rules/swift.md`, `commands/{onboard,release,
  grade-north-star}.md`, `agents/{apple-reviewer,xcode-build-debugger}.md`,
  `skills/release-ops/`, the spinner corpora, `statusline.sh`.

`settings.json` is **Advisory**: skeleton-shaped, repo-specific content, drift
reported and never blind-copied. It is the single place all wiring lives.

Two frontmatter rules that are easy to get wrong because they are asymmetric:

- Subagent `tools:` takes **tool names only**. `Bash(git diff:*)` there does
  not resolve and the tool is silently lost. Narrow shell access with
  `permissions.allow` in `settings.json` or a per-hook `if:` filter.
- Command `allowed-tools:` **does** take permission-rule syntax. The asymmetry
  is deliberate.

Side-effectful commands (`/onboard`, `/release`) set
`disable-model-invocation: true` so the model cannot trigger them on its own.

The spinner corpora (`.claude/spinner-verbs.txt`, `spinner-tips.txt`) are the
source of truth; Claude Code has no file-reference form, so
`scripts/sync_spinner_verbs.py` materializes them into `settings.json`.
`make spinner-check` is in the gate chain, so the two can never drift.

---

## 10. Hazards

Things that are true, surprising, and will cost you a day.

### The Mac app has no menu-bar surface (v1)

`MenuBarExtra` has an unfixed `setImage:` infinite-recursion crash on macOS 26
with no public trace or workaround, and the AppKit fallback (`NSStatusItem` in
an `NSApplicationDelegateAdaptor`) is a different app architecture. Rather than
ship either as canon, v1 ships a **main-window Mac app only** (ADR-0009). If
you add a menu-bar surface, treat it as a spike with its own ADR and test it on
the current macOS before it becomes template canon.

### Watch "mirroring" is a demonstration, not a sync engine

Each side runs its **own local store**. The phone pushes context through the
`onSnapshot` fan-out; the watch **displays** the phone's state in a row, and
watch actions act on the *watch's* local store. There is no reconciliation, no
conflict resolution, and no ordering guarantee. This is deliberate: a correct
two-way sync engine is a feature, not a template seam.

The upgrade path, when you need real sync: pick a single source of truth
(usually the phone), give every mutation a monotonic identity, move
`WatchLink` to `transferUserInfo` for queued delivery instead of
`updateApplicationContext` (which keeps only the latest value), and add a
reconciliation pass on the watch. Budget it as a real feature with its own
spec — and remember the ~65 KB payload ceiling.

### App icons are deliberately empty

The template ships empty `AppIcon` wells. A placeholder icon that reaches
TestFlight is worse than a loud failure, so onboarding lists "drop a 1024×1024
master icon" as a first-run step and the fastlane `beta` lane **preflights icon
presence** and fails with a pointer here. Add the master icon for each app
target you kept (iOS, macOS, watchOS) before your first archive.

### Interactive widgets are not wired

`widgets-home` ships a display-only widget. Making it interactive is a small,
well-understood upgrade, deferred so the template's widget stays legible:

1. Add an `AppIntent` conforming to `AppIntent` (not `AudioStartingIntent`
   etc.) that performs the action through `CheckpointStore`, returning quickly
   — the system gives you a short budget.
2. Put a `Button(intent:)` (or `Toggle(isOn:intent:)`) in the widget view.
   Both require iOS 17+, which is inside our floor.
3. The intent runs in the **widget's** process, so it must reach the store
   through the App Group, then call `WidgetCenter.shared.reloadTimelines`.
4. Keep the view's `.containerBackground(_:for: .widget)` — an interactive
   widget still needs it.

### `pre-compact-apple.sh` vs the skeleton's retired `pre-compact.sh`

`sync_skeleton.py` lists `.claude/hooks/pre-compact.sh` as RETIRED. Ours is
named `pre-compact-apple.sh` precisely so that deletion never matches it, and
`make sync-skeleton --apply` **deletes** it even though `settings.json` wires
it. If a sync removes it, restore it. Same class of surprise:
`--apply` re-adds `serena-required.sh`, `serena-gate.sh` and
`rules/serena.md`, which ADR-0005 removed. They arrive unwired and inert —
delete them again.

### `.xcconfig` is the lowest precedence layer

`DEVELOPMENT_TEAM`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live
only in `Config/*.xcconfig`. The same key anywhere in `project.yml`, a
component file, or a `settingGroup` **silently overrides** the xcconfig, and
the xcconfig looks broken. `verify.py` greps the whole YAML surface and fails
if any of the three appears outside `Config/`.

### MCP servers stay pending until you trust the workspace

A cloned repo cannot approve its own `.mcp.json`. `enableAllProjectMcpServers`
committed to project settings is inert in an untrusted folder, and
`headersHelper` — which runs a shell command — does not execute until the
workspace-trust dialog is accepted. Run `claude` once interactively in the new
repo before wondering why GitHub MCP is missing.

---

## 11. Where to look next

- `MAP.md` — the what-breaks-what table.
- `docs/adr/` — nine decisions with their reasoning.
- `specs/_build/` — construction-time contracts and research. Deleted at the
  end of construction, as designed; git history (pre-v0.8.0) preserves it.
  The load-bearing rules it froze live on in `.claude/rules/swift.md`,
  `CONVENTIONS.md` and the ADRs.
- `lang-swift-apple` skill references — the deep Swift/Apple material this
  guide deliberately does not duplicate.
