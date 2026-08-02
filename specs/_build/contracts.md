# Frozen contracts — template-apple-swift construction

> **Status: FROZEN v1 (post-research gate, 2026-08-02).** All R1–R5 spec deltas
> applied. Implementation waves code against THIS document, never against
> sibling agents' work-in-progress. Full research evidence:
> `specs/_build/research/R{1..5}-*.md` (R4 is the Swift-signature bible for
> W1B/W1C; R2 §Capability-audit lists xcodegen natives W1A must use; R1 Δ6 is
> the normative Fastfile skeleton for W2B; R5 is the settings/frontmatter bible
> for W2D/W2E). `specs/_build/` is construction scaffolding and is deleted
> before the template is tagged.

## 1. Identity tokens (the rename contract)

| Token | Value in template | Meaning |
|---|---|---|
| App name | `MyApp` | PascalCase Swift-safe name; target names, type prefixes, dir names |
| Bundle root | `com.example.myapp` | iOS + macOS app bundle ID (Universal Purchase: identical) |
| App Group | `group.com.example.myapp` | one string, 8 entitlements + 1 Swift constant |
| Team | `ABCDE12345` | placeholder team ID |
| Display name | `MyApp` | Info.plist display names |
| Slug | `myapp` | lowercase; BGTask IDs, scheme-adjacent identifiers |

Generator substitution order is **longest-first**: `group.com.example.myapp` →
`com.example.myapp` → `MyApp` → `myapp`. Post-rename lint asserts zero residual
tokens outside `template/` (which is deleted anyway). Binary files (png, car,
ttf) are on a skip-list. Everything checked in MUST compile with the tokens
as-is — tokens are valid identifiers, never `__PLACEHOLDER__` syntax.

## 2. Target & bundle ID registry (superset)

| Target | Type | Platform | Bundle ID | Prunable? |
|---|---|---|---|---|
| `MyApp` | application | iOS | `com.example.myapp` | never |
| `MyAppMac` | application | macOS | `com.example.myapp` | component `mac` |
| `MyAppWatch` | application | watchOS | `com.example.myapp.watch` | component `watch` |
| `WatchComplications` | app-extension | watchOS | `com.example.myapp.watch.complications` | component `complications` |
| `HomeWidget` | app-extension | iOS | `com.example.myapp.homewidget` | component `widgets-home` |
| `LiveActivity` | app-extension | iOS | `com.example.myapp.liveactivity` | component `live-activity` |
| `NotificationService` | app-extension | iOS | `com.example.myapp.notificationservice` | component `nse` |
| `MacWidget` | app-extension | macOS | `com.example.myapp.macwidget` | component `widget-mac` |
| `MyAppTests` | bundle.unit-test | iOS | `com.example.myapp.tests` | never |
| `MyAppUITests` | bundle.ui-testing | iOS | `com.example.myapp.uitests` | never (doubles as snapshot driver) |

Rules baked in from Pennywise/skill gotchas:
- Extension bundle IDs = **immediate host ID + exactly one segment** (ITMS-90347).
- Watch app MUST be a `dependencies:` entry on `MyApp` or it is silently absent
  from the .ipa (Pennywise P0-1).
- `MyAppWatch` gets `INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.example.myapp`
  and needs the App Group entitlement even before using it (exportArchive exit-70
  pairing failure otherwise).
- `NSSupportsLiveActivities` lives in the **host** Info.plist, never the extension's.
- Every extension: `SKIP_INSTALL: YES`. macOS targets: hardened runtime + sandbox.
- Raw xcodegen settings nest under `base:` (siblings of `groups:` are silently dropped).
- No bare `packages:` key with only comments (parses null → xcodegen error).
- `WidgetFamily.accessoryCorner` is watchOS-only and
  `WidgetFamily.systemExtraLargePortrait` is iOS 27 **beta** — neither may appear
  in an iOS/macOS `supportedFamilies` array on the Xcode 26 SDK. (R4 V9)
- Every widget/complication view MUST call `.containerBackground(_:for: .widget)`
  or the system renders an "adopt containerBackground" placeholder instead of the
  widget. (R4 V8)

## 3. Component registry (IDs are FROZEN — generator + markers + docs all key on these)

| ID | Brings | Requires |
|---|---|---|
| `mac` | MyAppMac target, mac entitlements/plist/privacy, mac AGENTS.md | — |
| `watch` | MyAppWatch target + WCSession seams | — |
| `complications` | WatchComplications target | `watch` |
| `widgets-home` | HomeWidget target | — |
| `widget-mac` | MacWidget target | `mac` |
| `live-activity` | LiveActivity target + SessionActivityAttributes usage | — |
| `nse` | NotificationService target + host `aps-environment` entitlement + AppDelegate APNs registration block | — |
| `swiftdata` | `@Model` Checkpoint + SwiftData `CheckpointPersisting` impl + ModelContainer wiring | — |
| `store` | `Shared/Capabilities/Store/**` (StoreKit 2 paywall stub) + Settings section | — |
| `account` | `Shared/Capabilities/Account/**` (SIWA + CloudKit stub) + SIWA/iCloud entitlements | — |
| `health` | `Shared/Capabilities/Health/**` + HealthKit entitlement + usage strings (default OFF) | — |

Derived (not asked, computed): `universal_purchase` = `mac` enabled;
push entitlement rides `nse` (and `live-activity` push-token registrar stub is
marker-gated on `nse` too, v1).

## 4. Cross-target Swift contracts (implementation waves MUST match exactly)

**Isolation is explicit everywhere in this template.** Every type carries either
`@MainActor` or `nonisolated`; nothing relies on `SWIFT_DEFAULT_ACTOR_ISOLATION`.
This keeps the sources compiling identically under Xcode 26's new-project
default (`MainActor`) and the legacy default (`nonisolated`). The types that
MUST be `nonisolated`: every `TimelineProvider` conformance, the
`UNNotificationServiceExtension` subclass, the `WCSessionDelegate` conformance,
`Shared/Sync/WidgetSync.swift`'s types, `SessionActivityAttributes`, and
`Shared/Theme/Theme.swift`. (R4 V2)

### 4.1 WidgetSync (App Group bridge) — `Shared/Sync/WidgetSync.swift`
```swift
public nonisolated enum WidgetAppGroup {
    public static let suiteName = "group.com.example.myapp"
}

public enum WidgetSyncKey: String {
    case payloadVersion  = "sync.payloadVersion"   // Int, currently 1
    case sessionStartedAt = "sync.sessionStartedAt" // Double unix seconds; 0 = no session
    case todayCount      = "sync.todayCount"        // Int
    case lastUpdatedAt   = "sync.lastUpdatedAt"     // Double unix seconds
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var sessionStartedAt: Date?
    public var todayCount: Int
    public var lastUpdatedAt: Date
}

public nonisolated enum WidgetSync {
    public static let payloadVersion = 1
    public static func write(_ snapshot: WidgetSnapshot)  // host apps + NSE write
    public static func read() -> WidgetSnapshot?          // extensions read
}
```
Host (iOS/mac/watch apps) writes on every store mutation; widgets/complications
read-only; NSE writes (its whole job). No other cross-process channel exists.
All four types in this file (`WidgetAppGroup`, `WidgetSyncKey`, `WidgetSnapshot`,
`WidgetSync`) are explicitly `nonisolated` because they are read from
`nonisolated` `TimelineProvider` conformances and from the Notification Service
Extension. Do not let `SWIFT_DEFAULT_ACTOR_ISOLATION` decide their isolation.
(R4 V2/V28)

### 4.2 Live Activity attributes — `Shared/SessionActivityAttributes.swift`
Guarded `#if os(iOS)` (NOT `canImport(ActivityKit)` — imports on macOS but types unavailable).
```swift
public nonisolated struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var startedAt: Date
        public var count: Int
    }
    public var sessionName: String
}
```

### 4.3 CheckpointStore — `Shared/Store/CheckpointStore.swift`
```swift
public struct SessionState: Codable, Equatable, Sendable {
    public var startedAt: Date?
    public var isActive: Bool { startedAt != nil }
}

public struct Checkpoint: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var note: String?
}

@MainActor
public protocol CheckpointPersisting {
    func load() throws -> [Checkpoint]
    func save(_ checkpoints: [Checkpoint]) throws
}
// Always-on impl: InMemoryCheckpointStore (+ UserDefaults-backed variant OK).
// `swiftdata` component adds SwiftDataCheckpointStore + @Model mirror type.
//
// @MainActor, NOT Sendable: SwiftData's ModelContext is not Sendable and
// ModelContainer.mainContext is @MainActor-isolated, so a Sendable protocol
// could only be satisfied with @unchecked. CheckpointStore is @MainActor
// anyway, so a main-actor protocol costs nothing and stays honest. (R4 V20)

@MainActor @Observable
public final class CheckpointStore {
    public private(set) var session: SessionState
    public private(set) var checkpoints: [Checkpoint]
    public var todayCount: Int { get }        // checkpoints logged today
    public init(persistence: any CheckpointPersisting)
    public func startSession()
    public func endSession()
    @discardableResult public func logCheckpoint(note: String?) -> Checkpoint
}
```
Every mutation calls `WidgetSync.write(...)` and (iOS, when `live-activity` on)
notifies `LiveActivityController`. Store is the ONLY mutation path.

### 4.4 App Intents — `MyApp/Intents/CheckpointIntents.swift`
`StartSessionIntent`, `EndSessionIntent`, `LogCheckpointIntent` +
`MyAppShortcuts: AppShortcutsProvider`. All route through `CheckpointStore`.
Metadata uses `static let` (never `static var` — Swift 6 rejects stored static
vars); `perform()` is `@MainActor func perform() async throws -> some IntentResult & ProvidesDialog`.
`openAppWhenRun` is used at the iOS 18 floor and is deprecated at iOS 26 in
favour of `supportedModes: IntentModes` — carry the migration comment.
Every `AppShortcut` phrase must contain the `\(.applicationName)` token, and
`shortTitle:` + `systemImageName:` are non-optional. (R4 V11–V14)

### 4.5 Theme — `Shared/Theme/Theme.swift`
Design-token chokepoint (`Theme.color.*`, `Theme.font.*`, `Theme.spacing.*`,
`Theme.radius.*`). System fonts only (no bundled ttf); `Theme.registerFonts()`
seam exists as a documented no-op, called from every `@main` and every
`WidgetBundle.init()` so custom fonts drop in later without archaeology.
Views NEVER use magic numbers / hex literals / ad-hoc fonts.

## 5. Swift component markers

Grammar (whole-line, exact):
```
// @template:<component-id> BEGIN
...component-only code...
// @template:<component-id> END
```
Marker blocks appear ONLY in files enumerated in `template/components.yaml`
(`marker_files:` list, cap ≤8). Everything else a component owns is
whole-file/whole-dir (preferred). Nesting forbidden (blocks for DIFFERENT
components may sit adjacent inside one closure — MyAppApp's onSnapshot fan-out
does this; stripping any subset leaves compiling code). `template/tmpl/prune.py`
strips blocks for disabled components; `verify.py` asserts no orphan markers.

**Markers are Swift-only.** The Wave-1 gate REJECTED a `#`-comment YAML marker
grammar (W1A Q3): per-component YAML keys live in capability/junction include
fragments instead (§6), so pruning YAML is always file-level. Actual marker
files as built (Wave-1 gate, 2026-08-02): `MyApp/MyAppApp.swift` (swiftdata,
nse, live-activity, watch), `Shared/Store/CheckpointStore.swift` (swiftdata),
`MyApp/Views/SettingsView.swift` (store, account, health),
`MyAppMac/MacRootView.swift` (store, account). Component test files are
whole-file owned (no markers in tests).

## 6. project.yml composition (xcodegen-native, ADR-0006)

- Root `project.yml`: `name`, `options` (`minimumXcodeGenVersion: '2.46.0'`,
  deployment targets, `createIntermediateGroups`, `disabledValidations:
  [missingConfigFiles]`; **no `bundleIdPrefix`** — see below), `settingGroups`,
  `targetTemplates` (extension shape) + `schemeTemplates`, `configFiles`
  wiring, `packages` (commented until needed — the key itself must be
  commented out, not left with a null value), always-on targets (MyApp,
  MyAppTests, MyAppUITests), top-level `schemes`, and an `include:` list of
  component files.
- **Every `include:` entry MUST use the object form with
  `relativePaths: false`.** The string form defaults to `relativePaths: true`,
  which re-roots every path in the included file at that file's own directory
  (`xcodegen/components/` here) and breaks all `sources`, `configFiles`,
  `entitlements`, `info`, `schemes` and `packages` paths. Canonical shape:
  ```yaml
  include:
    - path: xcodegen/components/mac.yml
      relativePaths: false
    - path: xcodegen/components/watch.yml
      relativePaths: false
  ```
- **No `options.bundleIdPrefix`.** Every target declares an explicit
  `PRODUCT_BUNDLE_IDENTIFIER`. `bundleIdPrefix` would auto-generate
  `com.example.HomeWidget` for any target that forgot one — plausible, wrong,
  and an ITMS-90347 rejection. A missing ID must fail loudly instead.
  `verify.py` asserts: every target has an explicit ID, and every extension's
  ID is its host's ID plus exactly one dot-segment.
- `xcodegen/components/<component-id>.yml`: that component's targets AND its
  merge fragments (host `dependencies:` edge, scheme additions, per-component
  entitlement/Info keys on host targets).
- **Prune = delete component file + remove its `include:` line.**
- **RESOLVED (R2).** XcodeGen merges included specs additively: dictionaries
  recurse, **arrays concatenate** (`merged[key] = (base + array)` in
  `Sources/ProjectSpec/SpecFile.swift`), and scalars are replaced. The root
  spec is merged *on top* of the reduced includes, so root wins scalar
  conflicts and root's array items land *after* the includes'. A component
  file contributing `targets.MyApp.dependencies: [{target: MyAppWatch}]`
  therefore appends. **The `# @component:<id>` tagged-line contingency is
  withdrawn — no yml splicing of any kind exists.**
  Constraints that follow:
  - There is **no deduplication**. Exactly one component file may contribute
    any given dependency edge, source entry, or scheme-target entry.
  - Root must not restate anything a component contributes.
  - Per-key override is `:REPLACE` (suffix on the key, any depth) — reserved
    for emergencies; v1 uses none.
  - A spec included twice is merged once (path-set guard), so shared fragments
    between component files are safe.
- **Prefer xcodegen-generated entitlements and Info.plist** (decision 10;
  R2 capability audit): a target's `entitlements: {path, properties}` and
  `info: {path, properties}` blocks let component files contribute
  per-component keys (e.g. `nse.yml` merges `aps-environment` into the host's
  entitlements properties) so pruning a component automatically drops its keys
  — eliminating most of `plists.py`. On-disk hand-authored plists remain ONLY
  where generation can't express the content (`PrivacyInfo.xcprivacy` always;
  anything else W1A must justify in a file comment). W1A finalizes the
  per-target mode; `verify.py` checks whichever mode ships.
- **Toolchain pins (as of 2026-08-02).** Xcode **26.6** (17F113, Swift 6.3) is
  both floor and ceiling — App Store submissions require Xcode 26, and Xcode 27
  is beta. `SWIFT_VERSION: '6.0'` (a *language mode*; there is no 6.2/6.3
  value). Every target also sets Xcode 26's new-project defaults:
  `SWIFT_APPROACHABLE_CONCURRENCY: YES` and
  `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`. XcodeGen pinned via
  `options.minimumXcodeGenVersion: '2.46.0'`.
- Capability components that add no target AND no entitlement/Info keys
  (`swiftdata`, `store`) need no `xcodegen/components/<id>.yml`. Their source
  directories are declared once in the root spec as
  `{ path: Shared/Capabilities/<X>, optional: true }`, and the umbrella
  `Shared` source entry carries `excludes: ["Capabilities/**"]` so files are
  never double-referenced. Pruning them is `rm` + marker strips — zero YAML.
- Capability components WITH entitlement/Info keys get **fragment-only include
  files** (`account.yml`, `health.yml` — no targets, just `targets.<Host>`
  property contributions), and cross-product keys get **junction fragments**
  (`account-mac.yml`, included iff account ∧ mac) — a fragment naming
  `targets.MyAppMac` when `mac` is pruned would break xcodegen, so neither
  single-component file may own those lines. `template/components.yaml
  includes:` maps every include file to its required components; the generator
  keeps an entry iff ALL requires are enabled. Ten include files total: seven
  target-bearing (`mac`, `watch`, `complications`, `widgets-home`,
  `widget-mac`, `live-activity`, `nse`) + three capability/junction fragments.
  (Gate note: this REPLACES both the Wave-1 `#`-form YAML markers and the
  earlier "six target-bearing components" text.)
- `Config/Versions.xcconfig`: `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`
  ONLY — written by `ci_scripts/ci_post_clone.sh` / release lanes; never patched
  into project.yml. `Config/Shared.xcconfig`: `DEVELOPMENT_TEAM` (+ future
  team-wide settings) so onboarding rewrites exactly one file for signing.
  An `.xcconfig` is the lowest layer of Xcode's build-setting precedence: any
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` / `DEVELOPMENT_TEAM` written
  into `project.yml` (or a component file, or a `settingGroup`) **silently
  overrides the xcconfig**. `verify.py` therefore greps the whole
  `xcodegen/` + `project.yml` surface and fails if any of those three keys
  appears outside `Config/*.xcconfig`.

## 7. Version contract (ADR-0007)

`VERSION` = plain semver (skeleton standard; `bump_version.py` /
`check_version_bumped.py` gates). `MARKETING_VERSION := $(cat VERSION)`,
`CURRENT_PROJECT_VERSION := $(git rev-list --count HEAD)` — materialized ONLY
into `Config/Versions.xcconfig` by ci_post_clone.sh (Xcode Cloud), release lanes
(fastlane), or `make bootstrap` (local dev convenience). Pennywise's
MAJOR=/MINOR_BASE= format and pre-commit MINOR_BASE auto-bump are dead.

## 8. Fastlane surface (ADR-0002; R1-refined, FROZEN)

Lane names are API: `bootstrap_asc`, `beta`, `screenshots`, `metadata`,
`release`, `certs`, `status`, `mac_beta`, `notarize`. Make targets delegate
1:1: `make testflight|screenshots|metadata-push|release|asc-status|asc-bootstrap|notarize-mac`.
**Structure decision (gate-resolved):** NO `platform :mac` block — all lanes
live in `platform :ios`; `mac_beta`/`notarize`/mac-metadata gate on the `mac`
component internally and pass `platform: "osx"` params where needed (R1 Δ6
"simpler reading"). Normative Fastfile skeleton: R1-fastlane.md Δ6.

**Auth.** `app_store_connect_api_key` invoked explicitly from `before_all`
with our own env names: `APP_STORE_CONNECT_API_KEY` (base64 `.p8`) **or**
`APP_STORE_CONNECT_API_KEY_P8_PATH`, plus `APP_STORE_CONNECT_API_KEY_ID` and
`APP_STORE_CONNECT_API_ISSUER`. (fastlane's own `APP_STORE_CONNECT_API_KEY_KEY_ID`
/ `_ISSUER_ID` / `_KEY` env names are deliberately NOT used; the Fastfile
reads ours and passes them as parameters.) `duration: 1200`, `in_house: false`.
The key MUST be a **Team** key — Individual keys cannot use provisioning
endpoints or notarytool.

**`bootstrap_asc` is capability-limited by Apple, not by us.** The App Store
Connect API has no create-app endpoint and `produce` authenticates only with
an Apple ID + 2FA session (both its Dev-Portal and its ASC half). Therefore:
`bootstrap_asc` registers/verifies **all bundle IDs and their capabilities**
through `Spaceship::ConnectAPI::BundleId` + `BundleIdCapability` with the API
key (this works), and **checks** for (a) the ASC app record and (b) the App
Group identifier, failing with an actionable pointer to `docs/asc-setup.md`
when either is missing. App-record creation, App Group creation, and iCloud
container creation are the documented manual residue. An opt-in Apple-ID path
(`FASTLANE_USER` + `FASTLANE_SESSION` from `fastlane spaceauth`) may call
`produce` interactively — never in CI.

**Signing.** Default automatic/cloud: works for App Store distribution because
Xcode 13+ cloud-managed distribution certs keep the private key with Apple.
gym has NO native ASC-key/`-allowProvisioningUpdates` support — the lane
threads `-allowProvisioningUpdates -authenticationKeyPath/-authenticationKeyID/
-authenticationKeyIssuerID` through `xcargs:` AND `export_xcargs:`,
materialising the base64 key to a temp `.p8` first. `match` is an onboarding
opt-in and is the recommended path for Developer ID / notarised Mac builds;
when `match` is on, every CI lane calls `setup_ci`. `ExportOptions.plist` MUST
use the legacy method spellings (`app-store`, `developer-id`) — gym's
`export_method` whitelist rejects `app-store-connect`/`release-testing`.

**Ruby.** `Gemfile` + `Gemfile.lock` committed, `fastlane` pinned to
`2.237.0`, `.ruby-version` = `3.4.x`. No `Pluginfile` — every lane uses core
actions only. All Linux jobs export `LC_ALL=C.UTF-8 LANG=C.UTF-8`.
API-only lanes (`metadata`, `status`, `bootstrap_asc`, `pilot` distribute)
run on Linux; `beta`, `mac_beta`, `screenshots`, `notarize`, and `certs`
(keychain import) guard with an explicit `FastlaneCore::Helper.mac?` check —
gym does **not** fail closed on its own.

**Screenshots.** `SnapshotHelper.swift` (v1.30, `@MainActor`, Swift-6-safe)
vendored into `UITests/`; deliver matches screenshots by **pixel resolution**
(`<locale>/*.png` flat; 1320×2868 → `APP_IPHONE_67`). snapshot is iOS-sim
only — no Mac/Watch screenshot automation exists. `frameit` requires
ImageMagick → gated by `ops.frameit` (default false).

## 9. Answers file (onboarding I/O)

`template/answers.schema.json` is the schema; `template/answers.example.yaml`
documents every field; `template/ci-combos/*.yaml` are instances. Shape:

```yaml
identity:
  app_name: MyApp            # PascalCase, Swift identifier
  display_name: "MyApp"
  bundle_root: com.example.myapp
  team_id: ABCDE12345
components:                  # booleans, keys = component IDs (§3)
  mac: true
  watch: true
  complications: true
  widgets-home: true
  widget-mac: true
  live-activity: true
  nse: true
  swiftdata: true
  store: false
  account: false
  health: false
deployment:                  # floors; R2-verified defaults (Aug 2026)
  ios: "18.0"                # ~93% of active iPhones (iOS 26=79%, 18=14%)
  macos: "15.0"              # same Sept-2024 cohort as iOS 18
  watchos: "11.0"            # same Sept-2024 cohort as iOS 18
ops:
  ci_system: xcode_cloud     # xcode_cloud | github_actions | none
  signing: automatic         # automatic | match
  frameit: false             # frameit needs ImageMagick + community frames
  spinner_flavor: true       # write spinnerVerbs + spinnerTipsOverride into .claude/settings.json
  statusline: false          # wire .claude/statusline.sh (shadows a personal statusLine — opt in)
  autonomy: continue-until-blocked
  squash_history: false
```
The three deployment floors are one OS cohort by construction;
`answers.schema.json` warns if they are mixed across cohorts. A documented
`modern` preset (`26.0/26.0/26.0`) exists for apps that hard-adopt OS-26 design
APIs. Build SDK is always the latest stable Xcode's (26.6 as of 2026-08-02);
App Store submission has required Xcode 26 + the 26-line SDKs since 2026-04-28.
Wizard writes `template/answers.local.yaml` (gitignored) then runs the same
generator CI runs. Dependency violations are generator ERRORS, not silent fixes.

## 10. Research deliverable contract (Phase 1 agents)

Write to `specs/_build/research/R<n>-<slug>.md`. Structure: `## Verdicts`
(numbered, each: claim → evidence/citation → confidence), `## Spec deltas`
(exact changes to THIS file or ADRs, quoted), `## Capability audit` (decision-10
sub-task: native tool capabilities the current design under-uses), `## Sources`.
Executive summary ≤40 lines returned as final message. No file outside
`specs/_build/research/` may be touched by research agents.
*(Historical — research complete; deltas applied at the 2026-08-02 gate.)*

## 11. MCP surface (ADR-0005; R3)

`.mcp.json` ships exactly three servers and zero secrets:
`github` (`type: http`, `https://api.githubcopilot.com/mcp/`),
`context7` (`type: http`, `https://mcp.context7.com/mcp`), and
`sequential-thinking` (stdio, `npx -y @modelcontextprotocol/server-sequential-thinking`).
The two HTTP servers share one `headersHelper`, `scripts/mcp/op-headers.sh`,
invoked through the git-root-resolving shell one-liner in
`specs/_build/research/R3-mcp.md` §V9. The script maps
`CLAUDE_CODE_MCP_SERVER_NAME` → `op://${MCP_OP_VAULT:-agentic}/…` and MUST
always exit 0 printing a JSON object (`{}` = no credential; one-line reason to
stderr). `{}` sends no `Authorization` header, so github falls through to
Claude Code's own OAuth flow (`/mcp`, `claude mcp login github`) and context7
falls through to its anonymous tier — both remain usable. Servers are **never
omitted**; a credential-less server degrades in place. No `${ENV_VAR}`
expansion for tokens; no credential in `args` (world-readable via `ps`).
No Serena server, hook, rule, flag, or workflow step exists anywhere.
`.env` / `.env.example` carry **no** MCP credentials; the MCP stanza in
`.env.example` is exactly:

```
# MCP servers take no credentials from this file.
# github + context7 resolve theirs at connect time from 1Password
# (scripts/mcp/op-headers.sh) and degrade to OAuth / anonymous tier without it.
```

context7's current tools are `resolve-library-id` and `query-docs`
(`get-library-docs` is gone) — no generated doc/prompt may name the old tool.

## 12. Claude Code surface contract (ADR-0008; R5)

Minimum supported Claude Code: **v2.1.144** (below this, custom `spinnerVerbs`
leak into the past-tense turn-completion message). `.claude/settings.json` is
Advisory under ADR-0008 and is the single place all wiring lives; every script
it references is a net-new Orphan file. Full settings skeleton + verdicts:
`specs/_build/research/R5-claude-surfaces.md` SD-2 (normative for W2D).
Headlines:

- **Spinner (decision 9): `spinnerVerbs: {mode: "append", verbs: [...]}` +
  `spinnerTipsOverride: {excludeDefault: false, tips: [...]}` — project scope
  works.** Corpus lives in `.claude/spinner-verbs.txt` + `.claude/spinner-tips.txt`
  (one entry per line, `#` comments; ≥120 verbs), materialized into
  settings.json by `scripts/sync_spinner_verbs.py` (`--check` mode joins the
  gate chain as `make spinner-check`; `make spinner-sync` rewrites). Generator
  runs spinner-sync AFTER token substitution (verbs may contain `MyApp`).
  Corpus rules: **gerunds only**, ≤~16 chars, no past-tense forms. The .txt
  files and settings.json are normal text for the rename engine (NOT on the
  binary skip-list).
- **Hooks wiring deltas vs skeleton baseline:** serena-required.sh +
  serena-gate.sh entries deleted (ADR-0005); all handlers use exec form
  (`args: []` — no quoting hack); `PostToolUse` matcher is `Edit|Write` (no
  `MultiEdit` — not a current tool name) plus a second Swift-only group
  `if: "Edit(**/*.swift)"` running `auto-lint-swift.sh` with
  `async: true, asyncRewake: true, timeout: 120`; `SessionStart` matcher is
  `startup|resume|clear|fork`; `permissions.deny` adds signing-material reads:
  `Read(./fastlane/.env*)`, `Read(**/AuthKey_*.p8)`, `Read(**/*.mobileprovision)`,
  `Read(**/*.p12)` (deny/allow arrays merge across scopes).
- **Subagent frontmatter (`.claude/agents/*.md`):** `tools:` takes **tool names
  only** — permission-rule syntax like `Bash(git diff:*)` silently strips the
  tool (live defect in skeleton + Pennywise agents; ours must not repeat it).
  `name` must not contain `:`. `model` ∈ `sonnet|opus|haiku|fable|<full-id>|inherit`.
- **Command frontmatter:** `allowed-tools:` DOES take permission-rule syntax
  (asymmetry is deliberate). Emit `Agent`, not `Task`. Side-effectful commands
  (`/release`, `/onboard`) MUST set `disable-model-invocation: true`.
- **Skills:** project skill invoked name = **directory name** (keep frontmatter
  `name` identical).
- **statusLine (opt-in via `ops.statusline`):** `{type: "command", command:
  "${CLAUDE_PROJECT_DIR}/.claude/statusline.sh", padding: 1, refreshInterval: 10}`;
  script budget <300ms, stdin JSON in / one line per row out, `$COLUMNS` not
  `tput`; forbidden: xcodebuild/xcodegen/network/git status. A project
  statusLine REPLACES a personal one — hence opt-in default false.
