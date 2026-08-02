# Questions / cross-partition notes — W1C (target sources)

Raised per the hard rule: W1C touched no file outside `MyApp/**/*.swift`,
`MyAppMac/**/*.swift`, `MyAppWatch/**/*.swift`, `HomeWidget/*.swift`,
`MacWidget/*.swift`, `LiveActivity/*.swift`, `WatchComplications/*.swift`,
`NotificationService/*.swift` — plus the three per-target `AGENTS.md` files the
W1C brief explicitly assigned (see Q1).

## Q1 — AGENTS.md ownership: brief vs `file-ownership.md`

`file-ownership.md` gives W2D "per-target `AGENTS.md` + `README.md` (all .md —
disjoint from W1C .swift)". The W1C brief item 15 explicitly directs W1C to
create `MyApp/AGENTS.md`, `MyAppMac/AGENTS.md`, `MyAppWatch/AGENTS.md` (≤40
lines each) and states extension dirs get none in v1. W1C followed the brief.
**W2D must treat these three files as already written** and not re-author them;
per-target `README.md` files remain W2D's.

## Q2 — `CheckpointStore.shared` does not exist (contracts §4.3 vs R4 §Group 4 crib)

R4's App Intents crib calls `CheckpointStore.shared`, but contracts §4.3
declares only `public init(persistence:)` — there is no singleton, and adding
one contradicts the frozen contract. Resolved the way R4's own Capability audit
A3 directs ("Action: use `@Dependency`"):

- `MyApp/MyAppApp.swift` `init()` calls
  `AppDependencyManager.shared.add(dependency: checkpointStore)`.
- Each intent declares `@Dependency private var store: CheckpointStore`.

**W1B must NOT add a `static let shared` to `CheckpointStore`.** If
`AppDependencyManager.add(dependency:)`/`@Dependency` fails to compile on the Mac
verification pass, the mechanical fallback is a `@MainActor enum` holder in the
app target registered from the same line — not a store singleton.

## Q3 — `LiveActivityController` surface consumed by `CheckpointStore`'s marker block

`MyApp/Services/LiveActivityController.swift` (whole-file `live-activity`
property) exposes, all `@MainActor` and inside `#if os(iOS)`:

```swift
LiveActivityController.shared
    .sync(session: SessionState, todayCount: Int)      // idempotent start/update/end
    .start(sessionName: String, state: SessionActivityAttributes.ContentState) -> Bool
    .update(_ state: SessionActivityAttributes.ContentState)
    .endAll(dismissal: ActivityUIDismissalPolicy = .immediate)
```

`sync(session:todayCount:)` is the single call the store's `live-activity`
marker block should make on every mutation (contracts §4.3). The other three are
R4's crib signatures, kept verbatim.

## Q4 — `components.yaml` file lists (W2A)

Two W1C files are component property but are not yet enumerated in
`template/components.yaml`:

- `live-activity.owns.files` must gain `MyApp/Services/LiveActivityController.swift`.
- `nse.owns.files` already lists `MyApp/AppDelegate.swift` — confirmed correct;
  the delegate is whole-file owned, not marker-gated.

W1C's marker files are exactly the three the registry predicts:
`MyApp/MyAppApp.swift` (swiftdata, nse, live-activity),
`MyApp/Views/SettingsView.swift` (store, account, health),
`MyAppMac/MacRootView.swift` (store, account). No other W1C file contains a marker.

## Q5 — Theme tokens consumed (W1B must guarantee these exist)

`Theme.registerFonts()`; `Theme.color.{background, surface, foreground, muted,
accent, danger}`; `Theme.font.{hero, title, headline, body, caption, label}`;
`Theme.spacing.{xxs, xs, small, medium, large}`; `Theme.radius.{small, large}`.
These are the `lang-swift-apple` `templates/Theme.swift.tmpl` names. No W1C view
uses a hex literal, a numeric padding, or an inline font.

## Q6 — Capability type surface consumed (contracts §3 names only directories)

`MyApp/Views/SettingsView.swift` and `MyAppMac/MacRootView.swift` reference:

- `store` → `PaywallView()` — no-argument init, `View`.
- `account` → `SignInView()` — no-argument init, `View`.
- `health` → `HealthService()` + `func requestAuthorization() async throws`
  (R4's `HealthProbe` crib under W1B's file name).

If W1B named any of these differently, the fix is confined to the three marker
blocks that reference them.

## Q7 — `WatchLink` surface consumed

`WatchLink.shared` (`@MainActor @Observable`), `.isReachable`, `.lastPayload`,
`.send(_ payload: WatchPayload)`, and
`WatchPayload(sessionStartedAt: Date?, todayCount: Int)` — R4 §Group 3 crib
verbatim. `MyAppWatchApp.init()` touches `WatchLink.shared` so `WCSession`
activates before any view queries reachability.

## Q8 — `Shared/Sync/WatchLink.swift` and the macOS target (W1A/W1B)

`xcodegen/components/mac.yml` excludes `**/WatchSync.swift` from `MyAppMac`'s
`Shared` sources but **not** `WatchLink.swift`. WatchConnectivity does not exist
on macOS, so either W1A adds the exclude or W1B guards the file with
`#if os(iOS) || os(watchOS)`. W1C cannot fix either file.

## Q9 — Accessibility identifiers (contract with `UITests/`)

`MyApp/Views/HomeView.swift` exports `startSessionButton` (shown when idle),
`endSessionButton` (shown when running), `logCheckpointButton`,
`checkpointNoteField`, `todayCountLabel`. `startSessionButton` is R4's crib name.
If W1B's `UITests/MyAppUITests/LaunchTests.swift` matches other identifiers, the
views are the side that should change — flag at the gate.

## Q10 — R4 A4 (interactive widget `Button(intent:)`) is not actionable in v1

R4's Capability audit A4 asks for `Button(intent: StartSessionIntent())` in the
home widget. `MyApp/Intents/CheckpointIntents.swift` is compiled only into the
`MyApp` target; `widgets-home.yml` gives `HomeWidget` just its own directory plus
`Shared/Sync/WidgetSync.swift`, `Shared/Theme` and the string catalog. Adopting
A4 requires moving the intents into `Shared/` **and** adding that path to
`widgets-home.yml` — a W1A + W1B + contracts §4.4 change, so W1C left the widgets
render-only. Same reason `Shared/Store/CheckpointStore.swift` is unreachable from
any extension.

## Q11 — `.modelContainer(_:)` is deliberately absent from the iOS Scene

`MyAppApp`'s `swiftdata` marker block builds the container inside
`makePersistence()` and hands it to `SwiftDataCheckpointStore`. Attaching
`.modelContainer(_:)` to the Scene as well would open the App Group store twice
in one process (two contexts, stale reads), because `SwiftDataCheckpointStore`
keeps its container `private` per R4's crib. Consequence: `@Query` is not
available to views by design, which is consistent with contracts §4.3 making the
store the only mutation path. If a future component wants `@Query`, expose the
container from `SwiftDataCheckpointStore` rather than building a second one.

## Q12 — Logging

W1C uses `os.Logger` directly in `MyApp/AppDelegate.swift` and
`NotificationService/NotificationService.swift` rather than `Shared/Log.swift`:
the NSE target's sources are its own directory plus `Shared/Sync/WidgetSync.swift`
only, so `Log` is not in that module, and using two namespaces in one component
would be worse than one. If W2 wants a single namespace, `Shared/Log.swift` must
be added to `nse.yml`'s sources first. No token, payload or Health value is
logged anywhere (`.claude/rules/security.md`); the APNs device token is reported
by byte count only.

## Q13 — Files created beyond the brief's enumeration

`MyApp/Views/RootView.swift` (TabView shell R4's crib assumes exists),
`MyApp/Services/AppInfo.swift` (the `BuildInfoProviding` shim),
`HomeWidget/HomeWidgetViews.swift`, `WatchComplications/ComplicationProvider.swift`,
`MyAppMac/Views/MacCheckpointList.swift`, `MyAppMac/Views/MacSessionControls.swift`
— all splits made to stay under the 250-line soft cap. W2A's manifest should be
built from the real tree, not from the brief's list.
