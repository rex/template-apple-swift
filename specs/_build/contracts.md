# Frozen contracts — template-apple-swift construction

> **Status: FROZEN v0 (pre-research).** Research wave (R1–R5) may amend ONLY via
> Fable updating this file at the Phase-1 gate, after which it is FROZEN v1 for
> implementation waves. Wave agents code against THIS document, never against
> sibling agents' work-in-progress. `specs/_build/` is construction scaffolding
> and is deleted before the template is tagged.

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

### 4.1 WidgetSync (App Group bridge) — `Shared/Sync/WidgetSync.swift`
```swift
public enum WidgetAppGroup {
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

public enum WidgetSync {
    public static let payloadVersion = 1
    public static func write(_ snapshot: WidgetSnapshot)  // host apps + NSE write
    public static func read() -> WidgetSnapshot?          // extensions read
}
```
Host (iOS/mac/watch apps) writes on every store mutation; widgets/complications
read-only; NSE writes (its whole job). No other cross-process channel exists.

### 4.2 Live Activity attributes — `Shared/SessionActivityAttributes.swift`
Guarded `#if os(iOS)` (NOT `canImport(ActivityKit)` — imports on macOS but types unavailable).
```swift
public struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
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

public protocol CheckpointPersisting: Sendable {
    func load() throws -> [Checkpoint]
    func save(_ checkpoints: [Checkpoint]) throws
}
// Always-on impl: InMemoryCheckpointStore (+ UserDefaults-backed variant OK).
// `swiftdata` component adds SwiftDataCheckpointStore + @Model mirror type.

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
whole-file/whole-dir (preferred). Nesting forbidden. `template/tmpl/prune.py`
strips blocks for disabled components; `verify.py` asserts no orphan markers.

Expected marker files (wave agents may propose changes at gate review only):
`MyApp/MyAppApp.swift` (ModelContainer/swiftdata; account env; nse APNs
registration call), `MyApp/AppDelegate.swift` (nse), `MyApp/Views/SettingsView.swift`
(store/account/health sections), `Shared/Store/CheckpointStore.swift`
(swiftdata impl selection + live-activity notification),
`MyAppMac/MacRootView.swift` (store/account sections), `Tests/MyAppTests/`
component test files are whole-file owned (no markers in tests).

## 6. project.yml composition (xcodegen-native, ADR-0006)

- Root `project.yml`: `name`, `options` (incl. `bundleIdPrefix: com.example`,
  deployment targets, `createIntermediateGroups`), `settingGroups`,
  `targetTemplates` (extension shape), `configFiles` wiring, `packages` (commented
  until needed), always-on targets (MyApp, MyAppTests, MyAppUITests), top-level
  `schemes`, and `include:` list of component files.
- `xcodegen/components/<component-id>.yml`: that component's targets AND its
  merge fragments (host `dependencies:` edge, scheme additions, extra
  `Shared/Capabilities/<X>` source entries for app targets).
- **Prune = delete component file + remove its `include:` line.**
- R2 MUST verify include deep-merge semantics for list-valued keys
  (`targets.MyApp.dependencies` contributed from a component file). Contingency
  if lists don't merge additively: those specific lines live in root project.yml
  tagged `# @component:<id>` and prune removes tagged lines. No other yml
  splicing exists.
- `Config/Versions.xcconfig`: `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`
  ONLY — written by `ci_scripts/ci_post_clone.sh` / release lanes; never patched
  into project.yml. `Config/Shared.xcconfig`: `DEVELOPMENT_TEAM` (+ future
  team-wide settings) so onboarding rewrites exactly one file for signing.

## 7. Version contract (ADR-0007)

`VERSION` = plain semver (skeleton standard; `bump_version.py` /
`check_version_bumped.py` gates). `MARKETING_VERSION := $(cat VERSION)`,
`CURRENT_PROJECT_VERSION := $(git rev-list --count HEAD)` — materialized ONLY
into `Config/Versions.xcconfig` by ci_post_clone.sh (Xcode Cloud), release lanes
(fastlane), or `make bootstrap` (local dev convenience). Pennywise's
MAJOR=/MINOR_BASE= format and pre-commit MINOR_BASE auto-bump are dead.

## 8. Fastlane surface (ADR-0002; R1 refines lane internals, NOT lane names)

Lane names are API: `bootstrap_asc` (produce: app record + all bundle IDs +
capabilities), `beta` (gym → pilot, wait, distribute), `screenshots`
(snapshot + frameit via MyAppUITests screenshot scheme), `metadata`
(deliver push of fastlane/metadata + fastlane/screenshots), `release`
(precheck → deliver submit), `certs` (match; only when signing=match), `status`
(Spaceship state dump), `mac_beta`, `notarize` (outside-store mac only).
Make targets delegate 1:1: `make testflight|screenshots|metadata-push|release|asc-status|asc-bootstrap|notarize-mac`.
Auth: `app_store_connect_api_key` with `APP_STORE_CONNECT_API_KEY` (base64 .p8)
or `APP_STORE_CONNECT_API_KEY_P8_PATH`, + `APP_STORE_CONNECT_API_KEY_ID`,
`APP_STORE_CONNECT_API_ISSUER`. Default signing: automatic/cloud
(`-allowProvisioningUpdates` + API key); `match` opt-in at onboarding.
Ruby: Gemfile + Gemfile.lock committed, `.ruby-version` = 3.3.x.

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
deployment:                  # floors; defaults per R2
  ios: "18.0"
  macos: "14.0"
  watchos: "10.0"
ops:
  ci_system: xcode_cloud     # xcode_cloud | github_actions | none
  signing: automatic         # automatic | match
  autonomy: continue-until-blocked
  squash_history: false
```
Wizard writes `template/answers.local.yaml` (gitignored) then runs the same
generator CI runs. Dependency violations are generator ERRORS, not silent fixes.

## 10. Research deliverable contract (Phase 1 agents)

Write to `specs/_build/research/R<n>-<slug>.md`. Structure: `## Verdicts`
(numbered, each: claim → evidence/citation → confidence), `## Spec deltas`
(exact changes to THIS file or ADRs, quoted), `## Capability audit` (decision-10
sub-task: native tool capabilities the current design under-uses), `## Sources`.
Executive summary ≤40 lines returned as final message. No file outside
`specs/_build/research/` may be touched by research agents.
