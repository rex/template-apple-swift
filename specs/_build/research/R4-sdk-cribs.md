# R4 — SDK contract crib sheets (write Swift blind on Linux, compile first-try on a Mac)

> Research deliverable per `contracts.md` §10. Date of research: **2026-08-02**.
> Target toolchain (from R2): **Xcode 26.6 / Swift 6.3 compiler / `SWIFT_VERSION: '6.0'`
> language mode / SDKs 26.5**. Deployment floors per contracts §9 (`iOS 18.0`,
> `macOS 14.0`, `watchOS 10.0`) — R2 proposes raising macOS→15.0 / watchOS→11.0;
> nothing in this document depends on that choice unless flagged.
>
> **Every signature below was read from Apple's live documentation JSON
> (`developer.apple.com/tutorials/data/documentation/<path>.json`) on 2026-08-02**,
> not from memory. Availability strings are quoted from that payload.
> Snippets are written to compile under Swift 6 language mode with
> **explicit isolation on every seam** (V2), so they are correct whether or not
> `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set.

---

## Verdicts

### Group 0 — cross-cutting (read this before any snippet)

**V1. Pennywise is NOT a Swift 6 reference. Every one of its 8 targets is pinned
to `SWIFT_VERSION: '5.10'`. Its concurrency patterns carry zero evidence about
strict-concurrency correctness, and at least three of them are hard compile
errors under Swift 6.**
Evidence: `/home/user/pennywise-apple-universal/project.yml` lines 57, 160, 221,
254, 291, 335, 408, 460, 481 — all `SWIFT_VERSION: '5.10'`. Confirmed
Swift-6-breaking patterns in that repo:
1. `Shared/WatchSync.swift:52-60` — `nonisolated func session(_:activationDidCompleteWith:error:)`
   captures the non-`Sendable` `WCSession` parameter inside `Task { @MainActor in … session.isPaired … }`.
   `WCSession` conforms only to `NSObject`/`CVarArg`/`CustomStringConvertible`/
   `Equatable`/`Hashable` — **not `Sendable`** (doc JSON `relationshipsSections`).
2. `Pennywise/Intents/PennywiseTrackingIntents.swift:16` — `static var title: LocalizedStringResource = "Start Tracking"`
   is nonisolated global mutable state → Swift 6 error. Must be `static let` (V17).
3. `PennywiseHomeWidget/PennywiseHomeWidget.swift:92` — `struct PennywiseHomeWidgetProvider: TimelineProvider`
   with no isolation annotation. Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
   this becomes a `@MainActor` witness for a nonisolated synchronous requirement → error (V2).
Use Pennywise for **API shape and target/plist wiring**; do not copy its
concurrency. Confidence: **high**.

**V2. Annotate isolation EXPLICITLY on every type in the template. Never let
`SWIFT_DEFAULT_ACTOR_ISOLATION` decide.** Concretely: `@MainActor` on stores,
view models and AppKit delegates; `nonisolated` on the five seam types listed
below. Code written this way compiles identically under
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Xcode 26's new-project default,
R2 V2b) and under `nonisolated` (the legacy default) — which is exactly the
property a template needs when it is authored blind and validated later.
Evidence: with MainActor default isolation an unannotated type is inferred
`@MainActor`; a `@MainActor` witness **cannot** satisfy a nonisolated
*synchronous* protocol requirement, and a `@MainActor` override cannot override a
nonisolated declaration — Apple Forums thread 806619 quotes the exact error
`Main actor-isolated initializer 'init(title:action:keyEquivalent:)' has different
actor isolation from nonisolated overridden declaration` for `NSMenuItem`
subclassing in Xcode 26.1 [S6]; SwiftLee and fatbobman document the same for
`@Model` nested types and give `nonisolated` before the type declaration as the
fix [S4][S5]; Swift issue 78518 / pointfree discussion 310 document the witness
form `main actor-isolated … cannot be used to satisfy nonisolated protocol
requirement` [S7][S8].

The exhaustive list of template types that MUST carry `nonisolated`:

| Type | Why |
|---|---|
| `MyAppTimelineProvider: TimelineProvider` (every widget/complication target) | `placeholder(in:)`, `getSnapshot(in:completion:)`, `getTimeline(in:completion:)` are nonisolated + synchronous |
| `NotificationService: UNNotificationServiceExtension` | `didReceive(_:withContentHandler:)` / `serviceExtensionTimeWillExpire()` are nonisolated overrides |
| `WatchLinkDelegate: NSObject, WCSessionDelegate` | all `WCSessionDelegate` methods are nonisolated + synchronous; `WCSessionDelegate` is **not** `@MainActor` |
| `enum WidgetSync` / `enum WidgetAppGroup` / `struct WidgetSnapshot` (contracts §4.1) | read from inside nonisolated timeline providers and from the NSE |
| `struct SessionActivityAttributes` (contracts §4.2) | decoded by the system off the main actor |

Types that need **no** annotation because the SDK already isolates them:
`App`, `Scene`, `View`, `Widget`, `WidgetBundle`, `ControlWidget`,
`StaticConfiguration`, `AppIntentConfiguration`, `ActivityConfiguration`,
`Query`, `UIApplicationDelegateAdaptor` — all declared
`@MainActor @preconcurrency` in the current SDK (verified individually).
Confidence: **high**.

**V3. `SWIFT_VERSION: '6.0'` is the language-mode value; `SWIFT_APPROACHABLE_CONCURRENCY = YES`
is safe to adopt, `SWIFT_DEFAULT_ACTOR_ISOLATION` is a coin-flip we should not
depend on.** R2 V2/V2b established the settings; V2 above establishes that our
code is invariant under the isolation default. Recommendation: set both to
Xcode-26 defaults (`YES` / `MainActor`) so the template matches what Xcode
produces, **and** write explicit annotations so a consumer who flips the setting
back is not broken. Confidence: **high**.

---

### Group 1 — ActivityKit (component `live-activity`)

**V4. `Activity.request(attributes:content:pushType:)` is `static … throws` — NOT
`async`. `update(_:)` and `end(_:dismissalPolicy:)` ARE `async`. There are now
four `request` overloads; the 4-arg `style:` overload is current, and the
`startDate:` overload is deprecated.**
Verbatim declarations from the doc JSON:
```swift
static func request(attributes: Attributes,
                    content: ActivityContent<Activity<Attributes>.ContentState>,
                    pushType: PushType? = nil) throws -> Activity<Attributes>
static func request(attributes: Attributes, content: …, pushType: PushType?,
                    style: ActivityStyle) throws -> Activity<Attributes>
static func request(attributes:content:pushType:style:alertConfiguration:start:) throws -> Activity<Attributes>
static func request(attributes:content:pushType:style:alertConfiguration:startDate:) // DEPRECATED
func update(_ content: ActivityContent<Activity<Attributes>.ContentState>) async
func update(_:alertConfiguration:) async
func end(_ content: ActivityContent<Activity<Attributes>.ContentState>?,
         dismissalPolicy: ActivityUIDismissalPolicy = .default) async
```
`ActivityContent` init is `init(state:staleDate:relevanceScore:)` (three labels;
`relevanceScore` defaults). `ActivityUIDismissalPolicy` = `.default` / `.immediate`
/ `.after(Date)` (all `static let`/`static func`, **not** enum cases).
`PushType` = `.token` and, new, **`static func channel(String) -> PushType`**.
`ActivityStyle` = `.standard` / `.transient`.
Availability: `Activity` iOS 16.1, `ActivityContent`/`update`/`end` iOS 16.2.
Pennywise's `LiveActivityManager` matches this shape and is still correct
(modulo Swift 6 isolation). Confidence: **high**.

**V5. Info.plist keys live on the HOST, not the extension.** `NSSupportsLiveActivities`
(iOS 16.1+) and `NSSupportsLiveActivitiesFrequentUpdates` are host-app keys;
Pennywise puts them in `Pennywise/Info.plist` and the extension plist carries only
`NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension`. Verified
by dumping both plists. contracts §2 already states this; it is correct.
Confidence: **high**.

**V6. `.supplementalActivityFamilies([.small])` (iOS 18+) is the opt-in that makes a
Live Activity render on Apple Watch. Our `live-activity` + `watch` component pair
currently ignores it.**
`@MainActor func supplementalActivityFamilies(_ families: [ActivityFamily]) -> some WidgetConfiguration`,
iOS 18.0; `ActivityFamily` = `.small` (watch) / `.medium` (phone). It is a
`WidgetConfiguration` modifier, so it hangs off `ActivityConfiguration`, not off a
view. Confidence: **high**.

**Crib — `Shared/SessionActivityAttributes.swift`**
```swift
import Foundation
#if os(iOS)
import ActivityKit

// `nonisolated` (V2): the system decodes this off the main actor.
// `#if os(iOS)` NOT `canImport(ActivityKit)` — the module resolves on
// Mac Catalyst/macOS builds where the types are unavailable (contracts §4.2).
public nonisolated struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var startedAt: Date
        public var count: Int
        public init(startedAt: Date, count: Int) {
            self.startedAt = startedAt
            self.count = count
        }
    }

    public var sessionName: String
    public init(sessionName: String) { self.sessionName = sessionName }
}
#endif
```

**Crib — `MyApp/Services/LiveActivityController.swift` (host side)**
```swift
import Foundation
#if os(iOS)
import ActivityKit

@MainActor
public final class LiveActivityController {
    public static let shared = LiveActivityController()
    private init() {}

    private var current: Activity<SessionActivityAttributes>? {
        Activity<SessionActivityAttributes>.activities.first
    }

    /// Idempotent. Returns false when the user disabled Live Activities.
    @discardableResult
    public func start(sessionName: String,
                      state: SessionActivityAttributes.ContentState) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let content = ActivityContent(state: state,
                                      staleDate: Date().addingTimeInterval(8 * 60 * 60))
        if let current {
            Task { await current.update(content) }
            return true
        }
        do {
            let activity = try Activity.request(
                attributes: SessionActivityAttributes(sessionName: sessionName),
                content: content,
                pushType: nil          // `.token` once the `nse` push registrar lands
            )
            observePushToken(for: activity)
            return true
        } catch {
            return false               // lock screen still works without it
        }
    }

    public func update(_ state: SessionActivityAttributes.ContentState) {
        guard let current else { return }
        let content = ActivityContent(state: state,
                                      staleDate: Date().addingTimeInterval(8 * 60 * 60))
        Task { await current.update(content) }
    }

    public func endAll(dismissal: ActivityUIDismissalPolicy = .immediate) {
        for activity in Activity<SessionActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: dismissal) }
        }
    }

    private func observePushToken(for activity: Activity<SessionActivityAttributes>) {
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                LiveActivityPushRegistrar.shared.register(activityID: activity.id, token: hex)
            }
        }
    }
}
#endif
```
Gotchas:
- `end(nil, dismissalPolicy:)` is legal — passing `nil` content keeps the last state.
- `activity.pushTokenUpdates` terminates when the activity ends, so the `for await`
  loop exits naturally; do **not** add a cancellation timer.
- `Activity.pushToStartToken` / `pushToStartTokenUpdates` are static and exist
  independently of any running activity — that is the "start a Live Activity from
  a push" path (iOS 17.2+), and it is the correct home for the `nse`-gated
  registrar stub.
- `ActivityAuthorizationInfo()` is cheap; `frequentPushesEnabled` is the gate for
  `NSSupportsLiveActivitiesFrequentUpdates`.

**Crib — `LiveActivity/MyAppLiveActivity.swift` (extension side, current DSL)**
```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct MyAppLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen / banner
            LockScreenView(state: context.state, name: context.attributes.sessionName)
                .activityBackgroundTint(Theme.color.surface)
                .activitySystemActionForegroundColor(Theme.color.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.count)", systemImage: "flag.checkered")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.sessionName)
                        .font(Theme.font.caption)
                }
            } compactLeading: {
                Image(systemName: "flag.checkered")
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "flag.checkered")
            }
            .keylineTint(Theme.color.accent)
        }
        .supplementalActivityFamilies([.small])   // iOS 18+: renders on Apple Watch
    }
}
```
Gotchas:
- `DynamicIslandExpandedRegion` placements are `.leading` / `.trailing` /
  `.center` / `.bottom`. The `expanded:` closure is a `DynamicIslandExpandedContent`
  builder — you may only put `DynamicIslandExpandedRegion` at its top level.
- The trailing/compact slots are width-clamped by the system; always `.frame(maxWidth:)`
  a `.timer` text or it will be truncated with an ellipsis.
- `Text(date, style: .timer)` self-advances without any `Activity.update` — this is
  the reason the Checkpoints domain only pushes state on lifecycle change.
- No continuous/repeating animations are permitted in a Live Activity; value-keyed
  implicit transitions are.
- Live Activity preview macro:
  `#Preview("LA", as: .content, using: SessionActivityAttributes(sessionName: "Focus")) { MyAppLiveActivity() } contentStates: { … }`
  where `ActivityPreviewViewKind` is `.content` or `.dynamicIsland(.compact|.expanded|.minimal)`.

---

### Group 2 — WidgetKit (components `widgets-home`, `widget-mac`, `complications`)

**V7. Use `TimelineProvider`, not `AppIntentTimelineProvider`, for our widgets.**
`AppIntentTimelineProvider` (iOS 17 / macOS 14 / watchOS 10) exists to back a
*user-configurable* widget and requires an `associatedtype Intent: WidgetConfigurationIntent`
plus `AppIntentConfiguration(kind:intent:provider:content:)`. Our widgets render a
single App-Group snapshot with no configuration surface, so `StaticConfiguration`
+ `TimelineProvider` is the correct and smaller shape. (Second-order note: because
`AppIntentTimelineProvider.snapshot`/`timeline` are `async`, that protocol is
*easier* under MainActor-default isolation — but `placeholder(in:)` is still
synchronous, so it needs `nonisolated` too, and the configuration intent is dead
weight.) Confidence: **high**.

**V8. `.containerBackground(_:for: .widget)` is mandatory for anything built against
the iOS 17+ SDK. Omitting it yields a widget that renders Apple's "Please adopt
containerBackground API" placeholder instead of your content.**
Evidence: `nonisolated func containerBackground<S>(_ style: S, for container: ContainerBackgroundPlacement) -> some View`,
iOS 17 / macOS 14 / watchOS 10; the requirement exists because StandBy, the watch
Smart Stack and tinted Home Screen all strip the background [S9][S10].
Use `.containerBackground(.fill.tertiary, for: .widget)` for system families and
`.containerBackground(.clear, for: .widget)` for `accessory*` families (the
lock-screen/complication chrome supplies its own vibrancy). Confidence: **high**.

**V9. `WidgetFamily.accessoryCorner` is `watchOS 9.0` ONLY and
`WidgetFamily.systemExtraLargePortrait` is **iOS 27 beta** — neither may appear in
a `supportedFamilies` array compiled for iOS on the Xcode 26 SDK.**
Evidence: per-case availability from doc JSON — `accessoryCorner` → `watchOS 9.0`;
`accessoryInline` → iOS 16.0 / watchOS 9.0; `systemExtraLargePortrait` →
`iOS 27.0 (beta); … visionOS 26.0`. This **narrows R2 V7**, which listed
`systemExtraLargePortrait` as an OS-27 additive item: it is not merely "don't adopt",
it is *not present* in the shipping SDK we build against. Confidence: **high**.

**Crib — `HomeWidget/HomeWidget.swift` (iOS; the Mac widget is the same file with
`.systemSmall/.systemMedium` families)**
```swift
import SwiftUI
import WidgetKit

struct CheckpointEntry: TimelineEntry {
    let date: Date
    let sessionStartedAt: Date?
    let todayCount: Int
}

// `nonisolated` (V2) — TimelineProvider's requirements are nonisolated + synchronous.
nonisolated struct CheckpointTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheckpointEntry {
        CheckpointEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-900), todayCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (CheckpointEntry) -> Void) {
        completion(Self.currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckpointEntry>) -> Void) {
        // The elapsed timer self-advances via Text(_, style: .timer); the only
        // thing a reload buys is a fresh todayCount.
        let policy: TimelineReloadPolicy = .after(.now.addingTimeInterval(15 * 60))
        completion(Timeline(entries: [Self.currentEntry()], policy: policy))
    }

    private static func currentEntry() -> CheckpointEntry {
        let snapshot = WidgetSync.read()
        return CheckpointEntry(date: .now,
                               sessionStartedAt: snapshot?.sessionStartedAt,
                               todayCount: snapshot?.todayCount ?? 0)
    }
}

struct HomeWidget: Widget {
    static let kind = "HomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CheckpointTimelineProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)   // V8 — mandatory
        }
        .configurationDisplayName("Checkpoints")
        .description("Your live session and today's checkpoint count.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct HomeWidgetBundle: WidgetBundle {
    init() { Theme.registerFonts() }          // WidgetBundle is @MainActor (SDK)
    var body: some Widget { HomeWidget() }
}

#Preview("rect", as: .accessoryRectangular) {
    HomeWidget()
} timeline: {
    CheckpointEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-600), todayCount: 4)
}
```
Gotchas:
- `WidgetBundle` is `@MainActor @preconcurrency protocol` (verified) — so
  `init()` is main-actor isolated. `Theme.registerFonts()` must therefore be
  `@MainActor` **or** `nonisolated`; if `Theme` is a `nonisolated enum`, the call
  is legal from a `@MainActor` init either way. Do not make `Theme` an actor.
- Exactly one `@main` per extension target. Splitting Live Activity and home widget
  into two targets (contracts §2) means two bundles — correct, and it is what
  Pennywise does.
- watchOS complications: same file shape, `supportedFamilies([.accessoryCircular,
  .accessoryRectangular, .accessoryInline, .accessoryCorner])`, and
  `.containerBackground(.clear, for: .widget)`. `.accessoryCorner` **only** inside
  a watchOS-only source file or `#if os(watchOS)` (V9).
- `Timeline(entries:policy:)` policies: `.atEnd`, `.after(Date)`, `.never`.
  Prefer `.after` + `WidgetCenter.reloadTimelines(ofKind:)` pushes from the host.
- Widget preview macro form is `#Preview(_:as:widget:timeline:)` — the trailing
  closure label is `timeline:` (array of entries), or `timelineProvider:` when you
  want the provider to generate them.

---

### Group 3 — WatchConnectivity (component `watch`) — THE concurrency trap

**V10. `WCSession` is not `Sendable` and `WCSessionDelegate` is not `@MainActor`.
The idiomatic-looking `nonisolated func session(_ session: WCSession, …) { Task { @MainActor in … session.isReachable … } }`
is a hard Swift 6 error: it captures a non-`Sendable` class across an isolation
boundary. So is forwarding the `[String: Any]` payload.**
Evidence: `WCSession` `relationshipsSections.Conforms To` = `CVarArg`,
`CustomDebugStringConvertible`, `CustomStringConvertible`, `Equatable`, `Hashable`,
`NSObject` — no `Sendable`. `WCSessionDelegate: NSObjectProtocol` with no
isolation annotation; every requirement is synchronous. `[String: Any]` is
`[String: any Any]`, which is not `Sendable`.
**The fix is mechanical: snapshot the values you need into `Sendable` locals
inside the nonisolated callback, then hop.** Confidence: **high**.

**Crib — `Shared/Sync/WatchLink.swift` (compiles on iOS and watchOS)**
```swift
import Foundation
import WatchConnectivity

/// Sendable value extracted from a WCSession callback.
public struct WatchPayload: Sendable, Codable {
    public var sessionStartedAt: Date?
    public var todayCount: Int
}

@MainActor
@Observable
public final class WatchLink {
    public static let shared = WatchLink()

    public private(set) var isReachable = false
    public private(set) var isActivated = false
    public private(set) var lastPayload: WatchPayload?

    private let delegate = WatchLinkDelegate()

    private init() {
        guard WCSession.isSupported() else { return }
        delegate.onState = { [weak self] activated, reachable in
            Task { @MainActor in
                self?.isActivated = activated
                self?.isReachable = reachable
            }
        }
        delegate.onPayload = { [weak self] payload in
            Task { @MainActor in self?.lastPayload = payload }
        }
        let session = WCSession.default
        session.delegate = delegate
        session.activate()
    }

    /// Latest-state-wins mirror. Cheap, coalesced, survives unreachability.
    public func pushContext(_ payload: WatchPayload) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let dict: [String: Any] = [
            "sessionStartedAt": payload.sessionStartedAt?.timeIntervalSince1970 ?? 0,
            "todayCount": payload.todayCount,
        ]
        try? WCSession.default.updateApplicationContext(dict)
    }

    /// Fire-and-forget command with guaranteed-eventually fallback.
    public func send(_ payload: WatchPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let dict: [String: Any] = [
            "sessionStartedAt": payload.sessionStartedAt?.timeIntervalSince1970 ?? 0,
            "todayCount": payload.todayCount,
        ]
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { _ in
                session.transferUserInfo(dict)     // queued fallback
            }
        } else {
            session.transferUserInfo(dict)
        }
    }
}

/// Isolation-free delegate shim. Every WCSessionDelegate requirement is
/// nonisolated + synchronous, so the WHOLE TYPE is nonisolated (V2) and it
/// converts to Sendable values BEFORE hopping to the main actor.
private final class WatchLinkDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    var onState: (@Sendable (Bool, Bool) -> Void)?
    var onPayload: (@Sendable (WatchPayload) -> Void)?

    private static func decode(_ dict: [String: Any]) -> WatchPayload {
        let unix = dict["sessionStartedAt"] as? TimeInterval ?? 0
        return WatchPayload(
            sessionStartedAt: unix > 0 ? Date(timeIntervalSince1970: unix) : nil,
            todayCount: dict["todayCount"] as? Int ?? 0
        )
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        // Extract Sendable scalars HERE. Never capture `session` in the closure.
        let activated = activationState == .activated
        let reachable = session.isReachable
        onState?(activated, reachable)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        onState?(session.activationState == .activated, reachable)
    }

    func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        onPayload?(Self.decode(ctx))
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onPayload?(Self.decode(message))
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        onPayload?(Self.decode(userInfo))
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) {
        onState?(session.activationState == .activated, session.isReachable)
    }
    #endif
}
```
Gotchas:
- `sessionDidBecomeInactive` / `sessionDidDeactivate` are **iOS-only** requirements
  (watch-switching). On watchOS they don't exist; guard with `#if os(iOS)` or the
  watch target fails to compile.
- `sessionCompanionAppInstalledDidChange` is **watchOS-only**.
- Channel semantics (all three exist for a reason; contracts should say which we use):
  | API | Delivery | Coalescing | Use for |
  |---|---|---|---|
  | `sendMessage(_:replyHandler:errorHandler:)` | immediate, requires `isReachable` | none | live commands while both apps are foreground |
  | `updateApplicationContext(_:)` | opportunistic, background | **latest wins** (single slot) | mirroring current state — our default |
  | `transferUserInfo(_:)` | guaranteed, background, FIFO queue | none (queue grows) | commands that must not be lost |
- `updateApplicationContext` `throw`s if the session isn't activated — hence the guard.
- Delegate must be set **before** `activate()`.
- The watch target still needs the App Group entitlement (contracts §2) so
  complications can read `WidgetSync` after the watch app mirrors.

---

### Group 4 — App Intents (contracts §4.4)

**V11. `static var title: LocalizedStringResource = "…"` is a Swift 6 error. Use
`static let`.** The protocol requirement is `static var title: LocalizedStringResource { get }`,
which a `static let` satisfies; a `static var` with a stored initializer is
nonisolated global mutable state. `LocalizedStringResource` and `IntentDescription`
both conform to `Sendable` (verified in `relationshipsSections`), so the `static let`
form is clean. Confidence: **high**.

**V12. `AppIntent.openAppWhenRun` is DEPRECATED as of iOS 26 / macOS 26 with the
message "Please provide 'supportedModes' instead". The replacement
`static var supportedModes: IntentModes` is iOS 26.0+ only.**
Evidence: doc JSON `platforms` for `openAppWhenRun` carries
`"deprecatedAt": "26.0", "message": "Please provide 'supportedModes' instead"` on
iOS/iPadOS/Mac Catalyst/macOS; `IntentModes` availability is `iOS 26.0 … watchOS 26.0`
with `.foreground`, `.background`, `.foreground(_:)`.
**Consequence for our iOS 18 floor:** Swift emits a deprecation warning only when
the deployment target is ≥ the deprecation version [S11][S12], so at `IPHONEOS_DEPLOYMENT_TARGET = 18.0`
`openAppWhenRun` is warning-free. Use it, and carry a one-line comment pointing at
`supportedModes` for whoever raises the floor to 26. Do **not** try to ship both —
a `@available(iOS 26.0, *) static var supportedModes` witness alongside
`openAppWhenRun` is untested surface we cannot validate from Linux.
Confidence: **high** on the deprecation; **medium** on the warning-suppression rule
(consistent Clang/Swift behavior, but not verified on a Mac).

**V13. `AppShortcut.init(intent:phrases:shortTitle:systemImageName:)` with
NON-optional `shortTitle`/`systemImageName` is current; the optional-parameter
overload is deprecated.** Pennywise's call site already passes both, so it is fine.
`AppShortcutsProvider: Sendable`, and `static var appShortcuts: [AppShortcut]` is a
*computed* requirement built with `@AppShortcutsBuilder` — computed statics are
Swift-6 legal. Confidence: **high**.

**V14. `AppIntent` inherits `Sendable`; `perform()` is `async throws -> Self.PerformResult`.
Because the requirement is `async`, a `@MainActor func perform()` witness IS
allowed — this is the one place MainActor isolation is free.** Confidence: **high**.

**Crib — `MyApp/Intents/CheckpointIntents.swift`**
```swift
import AppIntents
import Foundation

struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Session"           // V11: `let`
    static let description = IntentDescription("Start a MyApp session.")
    static let openAppWhenRun = true   // V12: → `supportedModes = .foreground` at an iOS 26 floor

    @MainActor                                                            // V14: legal (async requirement)
    func perform() async throws -> some IntentResult & ProvidesDialog {
        CheckpointStore.shared.startSession()
        return .result(dialog: "Session started.")
    }
}

struct LogCheckpointIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Checkpoint"
    static let description = IntentDescription("Log a checkpoint in the current MyApp session.")
    static let openAppWhenRun = false          // runs in-process, no UI needed

    @Parameter(title: "Note", requestValueDialog: "What should the note say?")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let checkpoint = CheckpointStore.shared.logCheckpoint(note: note)
        return .result(dialog: "Logged checkpoint at \(checkpoint.timestamp.formatted(date: .omitted, time: .shortened)).")
    }
}

struct EndSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Session"
    static let description = IntentDescription("End the current MyApp session.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        CheckpointStore.shared.endSession()
        return .result(dialog: "Session ended.")
    }
}

struct MyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start a \(.applicationName) session",
                "Start \(.applicationName)",
            ],
            shortTitle: "Start Session",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: LogCheckpointIntent(),
            phrases: [
                "Log a \(.applicationName) checkpoint",
                "Add a checkpoint in \(.applicationName)",
            ],
            shortTitle: "Log Checkpoint",
            systemImageName: "flag.checkered"
        )
        AppShortcut(
            intent: EndSessionIntent(),
            phrases: ["End my \(.applicationName) session"],
            shortTitle: "End Session",
            systemImageName: "stop.fill"
        )
    }
}
```
Gotchas:
- `\(.applicationName)` is the **only** interpolation token allowed in an
  `AppShortcutPhrase`, and **every phrase must contain it** — App Intents fails at
  build/validation time otherwise. Phrases are `AppShortcutPhrase<Intent>`, built
  from string literals with that token.
- `AppShortcutsProvider` must live in the **app** target (not an extension), or the
  shortcuts never register.
- `@Parameter` wrapped properties make the intent non-`Sendable`-derivable? No —
  `@Parameter` storage is `Sendable`; `struct` intents with only `@Parameter`
  properties satisfy `AppIntent: Sendable` automatically.
- The `CheckpointStore.shared` reference above is the pragmatic path. The **native**
  path is `AppDependencyManager` + `@Dependency` — see Capability audit A3.

---

### Group 5 — StoreKit 2 (component `store`)

**V15. Current shapes, all verified:**
```swift
static func products<Identifiers>(for: Identifiers) async throws -> [Product]
@MainActor func purchase(options: Set<Product.PurchaseOption> = []) async throws -> Product.PurchaseResult
static var updates: Transaction.Transactions            // AsyncSequence
static var currentEntitlements: Transaction.Transactions
func finish() async
@frozen enum VerificationResult<SignedType>             // .verified(T) / .unverified(T, VerificationError)
```
`Product.PurchaseResult` = `.success(VerificationResult<Transaction>)` / `.userCancelled`
/ `.pending`. Note `purchase(options:)` is `@MainActor` — call it from a view or a
`@MainActor` store, never from a detached task. `Product.currentEntitlement` (singular)
and `Transaction.currentEntitlement(for:)` are **deprecated**; use the plural
`Transactions` sequences. New `purchase(confirmIn: some UIScene / UIViewController / NSWindow, options:)`
overloads exist for multi-scene apps — not needed for our stub. Confidence: **high**.

**V16. For the `store` stub, use the API path (`Product.products` + `purchase` +
`Transaction.updates`), NOT `SubscriptionStoreView`.** `SubscriptionStoreView(groupID:)`
(iOS 17+) is excellent production UI but requires a real App Store Connect
subscription group; with the template's placeholder identifiers it renders a
failure/loading state and gives an agent no compilable seam to extend. The API path
degrades to a clean empty state (`products(for:)` returns `[]` for unknown IDs).
Ship `SubscriptionStoreView` as a commented alternative in the paywall view.
Confidence: **medium** (product judgement, not a fact).

**Crib — `Shared/Capabilities/Store/StoreCoordinator.swift`**
```swift
import Foundation
import StoreKit

@MainActor
@Observable
public final class StoreCoordinator {
    public private(set) var products: [Product] = []
    public private(set) var purchasedProductIDs: Set<String> = []
    public var isPro: Bool { !purchasedProductIDs.isEmpty }

    /// Replace with real IDs at onboarding; unknown IDs return [] (no throw).
    public static let productIDs: [String] = ["com.example.myapp.pro.yearly"]

    private var updatesTask: Task<Void, Never>?

    public init() {}

    public func start() {
        // Long-lived listener — Apple requires this to be running at launch so
        // Ask-to-Buy / interrupted purchases land.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    public func refresh() async {
        products = (try? await Product.products(for: Self.productIDs)) ?? []
        await refreshEntitlements()
    }

    public func purchase(_ product: Product) async throws {
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            owned.insert(transaction.productID)
        }
        purchasedProductIDs = owned
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? Self.checkVerified(result) else { return }
        purchasedProductIDs.insert(transaction.productID)
        await transaction.finish()
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }
}
```
Gotchas:
- `Transaction.updates` must be consumed by a task started at app launch, **not**
  by a view's `.task {}` — a view can be torn down mid-purchase.
- `@unknown default` on `PurchaseResult` (non-frozen enum in a system framework)
  keeps us source-compatible across SDKs. `VerificationResult` IS `@frozen`, so no
  `@unknown default` there.
- Always `await transaction.finish()`, including for `currentEntitlements` replays,
  or the transaction is redelivered forever.
- A `.storekit` configuration file lets the stub run in the simulator with no ASC
  setup; wire it in the scheme, not in `project.yml`.

---

### Group 6 — Sign in with Apple + CloudKit (component `account`)

**V17. Verified signatures:**
```swift
@MainActor struct SignInWithAppleButton
init(_ label: SignInWithAppleButton.Label,
     onRequest: (ASAuthorizationAppleIDRequest) -> Void,
     onCompletion: (Result<ASAuthorization, any Error>) -> Void)
func credentialState(forUserID userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState
func accountStatus() async throws -> CKAccountStatus
```
The `async` `credentialState(forUserID:)` and `accountStatus()` variants both exist
today — do not use the completion-handler forms. `SignInWithAppleButton.Label` =
`.signIn` / `.signUp` / `.continue`; `.signInWithAppleButtonStyle(_:)` takes
`.black` / `.white` / `.whiteOutline`. Confidence: **high**.

**Crib — `Shared/Capabilities/Account/AccountView.swift`**
```swift
import AuthenticationServices
import CloudKit
import SwiftUI

@MainActor
@Observable
public final class AccountCoordinator {
    public enum State: Sendable, Equatable {
        case unknown, signedOut, signedIn(userID: String), revoked
    }

    public private(set) var state: State = .unknown
    public private(set) var iCloudStatus: CKAccountStatus = .couldNotDetermine

    private static let userIDKey = "account.appleUserID"

    public init() {}

    public func refresh() async {
        iCloudStatus = (try? await CKContainer.default().accountStatus()) ?? .couldNotDetermine

        guard let userID = KeychainBox.read(Self.userIDKey) else {
            state = .signedOut
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        switch try? await provider.credentialState(forUserID: userID) {
        case .authorized:            state = .signedIn(userID: userID)
        case .revoked, .notFound:    KeychainBox.delete(Self.userIDKey); state = .revoked
        default:                     state = .unknown
        }
    }

    public func handle(_ result: Result<ASAuthorization, any Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential
        else { state = .signedOut; return }

        // `user` is the ONLY stable identifier. email/fullName arrive on first
        // authorization only — persist them here or they are gone forever.
        KeychainBox.write(Self.userIDKey, value: credential.user)
        state = .signedIn(userID: credential.user)
    }
}

public struct AccountView: View {
    @State private var coordinator = AccountCoordinator()

    public init() {}

    public var body: some View {
        VStack(spacing: Theme.spacing.medium) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                coordinator.handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)

            Text(verbatim: String(describing: coordinator.iCloudStatus))
                .font(Theme.font.caption)
        }
        .task { await coordinator.refresh() }
    }
}

/// Minimal Keychain sketch — kSecClassGenericPassword, one account per key.
enum KeychainBox {
    private static let service = "com.example.myapp.account"

    static func write(_ key: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ] as CFDictionary)
    }
}
```
Gotchas:
- Entitlements: `com.apple.developer.applesignin = [Default]` on the app target(s),
  plus `com.apple.developer.icloud-container-identifiers` +
  `com.apple.developer.icloud-services = [CloudKit]` for the `CKContainer` call.
  The `account` component owns both (contracts §3).
- `ASAuthorizationAppleIDProvider` also posts `.credentialRevokedNotification`;
  subscribing to it is the supported way to notice sign-out without polling.
- Never store the Apple user ID in `UserDefaults` — it is a stable cross-launch
  identifier and belongs in the Keychain (`.claude/rules/security.md`).
- `CKAccountStatus` = `.available`, `.noAccount`, `.restricted`,
  `.couldNotDetermine`, `.temporarilyUnavailable`. Treat everything but
  `.available` as "no cloud" rather than as an error.

---

### Group 7 — HealthKit (component `health`, default OFF)

**V18. Guard with `#if os(iOS)`, NOT `#if canImport(HealthKit)`.** `HKHealthStore`
availability is `iOS 8.0; … macOS 13.0; visionOS 1.0; watchOS 2.0` — HealthKit
imports and partially exists on macOS, so `canImport` is true there and the guard
does nothing. This is the same trap contracts §4.2 already documents for
ActivityKit. Confidence: **high**.

**V19. Use the Swift-concurrency query descriptors, not `HKSampleQuery`.**
```swift
func requestAuthorization(toShare typesToShare: Set<HKSampleType>,
                          read typesToRead: Set<HKObjectType>) async throws   // iOS 15+
struct HKSampleQueryDescriptor<Sample: HKSample>
init(predicates: [HKSamplePredicate<Sample>], sortDescriptors: [SortDescriptor<Sample>], limit: Int?)
func result(for: HKHealthStore) async throws -> [Sample]                      // iOS 15.4+
struct HKStatisticsQueryDescriptor                                            // sums/averages
```
Pennywise's `HealthKitManager` predates these; flag it as outdated. Confidence: **high**.

**Crib — `Shared/Capabilities/Health/HealthProbe.swift`**
```swift
#if os(iOS)                                    // V18 — NOT canImport
import Foundation
import HealthKit

@MainActor
@Observable
public final class HealthProbe {
    public private(set) var latestStepCount: Double?
    public private(set) var isAuthorized = false

    private let store = HKHealthStore()

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization() async throws {
        guard isAvailable else { return }
        let steps = HKQuantityType(.stepCount)
        try await store.requestAuthorization(toShare: [], read: [steps])
        isAuthorized = true
    }

    /// One sample query, modern async form.
    public func refreshLatestSteps() async throws {
        guard isAvailable else { return }
        let steps = HKQuantityType(.stepCount)
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: .now)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: steps, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: store)
        latestStepCount = samples.first?.quantity.doubleValue(for: .count())
    }
}
#endif
```
Gotchas:
- `NSHealthShareUsageDescription` (read) and `NSHealthUpdateUsageDescription`
  (write) must both be in the **host** Info.plist even if you only read — the
  `health` component owns those strings (contracts §3).
- `requestAuthorization` does **not** tell you whether the user granted read
  access; `authorizationStatus(for:)` only reports *write* permission. Never branch
  UI on it — query and handle empty results.
- Entitlement `com.apple.developer.healthkit = true`; the
  `com.apple.developer.healthkit.access` array is only for clinical records.
- Per `CLAUDE.md` §7 / `.claude/rules/security.md`: never log a sample value.

---

### Group 8 — SwiftData (component `swiftdata`)

**V20. `ModelContainer` IS `Sendable`; `ModelContext` is NOT. Therefore
`public protocol CheckpointPersisting: Sendable` (contracts §4.3) cannot be
satisfied by a SwiftData implementation without either an `@unchecked` lie or an
async/actor redesign. This is the one contracts §4 signature that is not
expressible cleanly under strict concurrency.**
Evidence: `relationshipsSections.Conforms To` — `ModelContainer` → `Equatable`,
**`Sendable`**, `SendableMetatype`; `ModelContext` → `Equatable`,
`SendableMetatype` only. `container.mainContext` is declared
`@MainActor var mainContext: ModelContext { get }`.
Proposed fix in Spec deltas (D1): make the protocol `@MainActor` and drop
`: Sendable`. Confidence: **high** on the facts; **high** on the fix.

**V21. `PersistentModel` does not inherit `Sendable`. Do not pass `@Model` instances
across actors.** (`PersistentModel` inherits `Equatable`, `Hashable`,
`Identifiable`, `Observation.Observable`, `SendableMetatype` — no `Sendable`.) The
`@Model` macro's `@attached(extension, conformances: … Sendable)` role list means
the macro *may* add the conformance; treat that as an implementation detail and
keep model objects main-actor-confined. Our `Checkpoint` value struct
(contracts §4.3) is the cross-boundary currency — the `@Model` class is a private
mirror. That design is already correct. Confidence: **medium-high**.

**Crib — `Shared/Store/SwiftDataCheckpointStore.swift`**
```swift
import Foundation
import SwiftData

@Model
final class CheckpointRecord {
    #Index<CheckpointRecord>([\.timestamp])
    var id: UUID
    var timestamp: Date
    var note: String?

    init(id: UUID, timestamp: Date, note: String?) {
        self.id = id
        self.timestamp = timestamp
        self.note = note
    }
}

/// SwiftData-backed persistence. @MainActor because it uses `container.mainContext`
/// (which is @MainActor) — see Spec delta D1.
@MainActor
public final class SwiftDataCheckpointStore: CheckpointPersisting {
    private let container: ModelContainer

    public init(container: ModelContainer) { self.container = container }

    /// Migration-free config (contracts scope): no migrationPlan, App-Group store
    /// so the same file is reachable from every host target.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            nil,
            schema: Schema([CheckpointRecord.self]),
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            groupContainer: .identifier(WidgetAppGroup.suiteName),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Schema([CheckpointRecord.self]),
                                  configurations: [configuration])
    }

    public func load() throws -> [Checkpoint] {
        let descriptor = FetchDescriptor<CheckpointRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try container.mainContext.fetch(descriptor)
            .map { Checkpoint(id: $0.id, timestamp: $0.timestamp, note: $0.note) }
    }

    public func save(_ checkpoints: [Checkpoint]) throws {
        let context = container.mainContext
        try context.delete(model: CheckpointRecord.self)
        for checkpoint in checkpoints {
            context.insert(CheckpointRecord(id: checkpoint.id,
                                            timestamp: checkpoint.timestamp,
                                            note: checkpoint.note))
        }
        try context.save()
    }
}
```

**Crib — wiring in `MyApp/MyAppApp.swift` (marker-gated, contracts §5)**
```swift
@main
struct MyAppApp: App {
    // @template:swiftdata BEGIN
    private let modelContainer: ModelContainer
    // @template:swiftdata END
    @State private var store: CheckpointStore

    init() {
        Theme.registerFonts()
        // @template:swiftdata BEGIN
        // Fail loudly in DEBUG; fall back to in-memory in RELEASE so a corrupt
        // store never bricks launch.
        let container = (try? SwiftDataCheckpointStore.makeContainer())
            ?? (try! SwiftDataCheckpointStore.makeContainer(inMemory: true))
        self.modelContainer = container
        _store = State(initialValue: CheckpointStore(
            persistence: SwiftDataCheckpointStore(container: container)))
        // @template:swiftdata END
        // (no-swiftdata build substitutes:)
        // _store = State(initialValue: CheckpointStore(persistence: InMemoryCheckpointStore()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        // @template:swiftdata BEGIN
        .modelContainer(modelContainer)
        // @template:swiftdata END
    }
}
```
Gotchas:
- `App.init()` is `@MainActor` (the `App` protocol is `@MainActor @preconcurrency`),
  so touching `mainContext` from `init` is legal.
- `.modelContainer(_:)` on a `Scene` also injects `\.modelContext` into the
  environment; that is what makes `@Query` work. **`@Query` is only valid inside a
  `View`** — never in a store, never in an extension.
- `ModelConfiguration(_:schema:isStoredInMemoryOnly:allowsSave:groupContainer:cloudKitDatabase:)`
  is the App-Group-capable initializer; the short
  `init(for:isStoredInMemoryOnly:)` cannot set `groupContainer`.
- `groupContainer: .identifier(...)` + `cloudKitDatabase: .none` = "shared with
  extensions, not synced". Turning CloudKit on later requires every property to be
  optional or defaulted — say so in `docs/`.
- Widgets/complications must **not** open the container. They read the App Group
  `UserDefaults` snapshot (contracts §4.1). Opening a SwiftData store from a
  timeline provider is the classic cause of widget timeouts.
- `#Index` / `#Unique` macros are iOS 18+; safe at our floor, remove if the floor
  ever drops.

---

### Group 9 — UNNotificationServiceExtension (component `nse`)

**V22. Override signatures are unchanged since iOS 10 and both are nonisolated —
so the NSE subclass must be `nonisolated` under MainActor-default isolation (V2).**
```swift
func didReceive(_ request: UNNotificationRequest,
                withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void)
func serviceExtensionTimeWillExpire()
func reloadTimelines(ofKind: String)      // WidgetCenter — extension-callable
func reloadAllTimelines()
```
Confidence: **high**.

**Crib — `NotificationService/NotificationService.swift`**
```swift
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif
import os

// `nonisolated` (V2): both overrides are nonisolated in the superclass.
nonisolated final class NotificationService: UNNotificationServiceExtension {
    private static let logger = Logger(subsystem: "com.example.myapp.notificationservice",
                                       category: "NSE")

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent

        // Always deliver, whatever happens below.
        defer { contentHandler(bestAttempt ?? request.content) }

        let userInfo = request.content.userInfo
        // iOS only routes a push here when aps.mutable-content == 1, but assert it
        // explicitly so the App-Group side effect is provably scoped.
        guard Self.isMutableContent(userInfo) else { return }

        let started = (userInfo["sessionStartedAt"] as? Double).flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
        }
        let today = userInfo["todayCount"] as? Int ?? 0

        WidgetSync.write(WidgetSnapshot(sessionStartedAt: started,
                                        todayCount: today,
                                        lastUpdatedAt: .now))
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "HomeWidget")
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        Self.logger.info("NSE mirrored snapshot and reloaded widget timelines")
    }

    override func serviceExtensionTimeWillExpire() {
        // ~30 s budget. The defer above already fired, but Apple's template
        // requires this safety net.
        if let bestAttempt { contentHandler?(bestAttempt) }
    }

    private static func isMutableContent(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let aps = userInfo["aps"] as? [AnyHashable: Any] else { return false }
        switch aps["mutable-content"] {
        case let n as Int:      return n == 1
        case let n as NSNumber: return n.intValue == 1
        case let b as Bool:     return b
        default:                return false
        }
    }
}
```
Gotchas:
- `INFOPLIST_KEY_NSExtensionPointIdentifier: com.apple.usernotifications.service`
  **and** `INFOPLIST_KEY_NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).NotificationService`
  — omitting the principal class is the classic "extension never fires" bug.
  (Pennywise `project.yml:332-333` gets this right.)
- The NSE needs the App Group entitlement; it does **not** need `aps-environment`
  (that rides the host).
- The host needs `UIBackgroundModes = [remote-notification]` and `aps-environment`.
- Do **not** activate a `WCSession` from an NSE — unreliable, and Pennywise
  explicitly documents avoiding it.
- Apple's silent-push budget is ~2-3/hour; the NSE (mutable-content, visible alert)
  is the documented escape hatch. On an iOS 26 floor the *native* answer is
  WidgetKit push — see Capability audit A1.

---

### Group 10 — macOS (component `mac`)

**V23. Ship no menu-bar surface in v1. `MenuBarExtra` is `nonisolated struct … macOS 13.0`
and still current API, but the macOS-26 menu-bar layer is demonstrably unstable —
independent reports cover both `MenuBarExtra` and hand-rolled `NSStatusItem`
(RenderBox/Metal shader failures leaving the status item unregistered;
`NSStatusItem.isVisible` returning `true` for hidden items).** This *strengthens*
R2 V6: the hazard is not merely "Pennywise saw a `setImage:` recursion", it is a
broader Tahoe menu-bar regression class, and `NSStatusItem` is not a guaranteed
escape. Record it as a hazard note in `MyAppMac/AGENTS.md`; do not add the surface.
Evidence: [S13][S14][S15]; Pennywise `MacAppDelegate.swift` header comment.
Confidence: **high** on the recommendation; **low** on any claim about the specific
bug's current status.

**V24. The macOS surface for v1 is `WindowGroup` + `Settings` + `SMAppService`.**
`Settings` is `nonisolated struct … macOS 11.0` (still current — it is *not*
deprecated in favour of anything). `SMAppService` is `macOS 13.0`; `SMAppService.mainApp.register()`
throws and `.status` reports `.enabled` / `.notRegistered` / `.notFound` / `.requiresApproval`.
Confidence: **high**.

**Crib — `MyAppMac/MyAppMacApp.swift`**
```swift
import ServiceManagement
import SwiftUI

@main
struct MyAppMacApp: App {
    @State private var store = CheckpointStore(persistence: InMemoryCheckpointStore())

    init() { Theme.registerFonts() }

    var body: some Scene {
        WindowGroup(id: "main") {
            MacRootView()
                .environment(store)
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowResizability(.contentMinSize)
        .commands { SidebarCommands() }

        Settings {
            MacSettingsView()
                .environment(store)
        }
    }
}

/// Login item. macOS 13+. Never call from a non-main context.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

// NOT shipped in v1 — hazard note only. If you add a menu bar surface,
// re-test on the current macOS before trusting either path:
//   MenuBarExtra("MyApp", systemImage: "flag.checkered") { MenuContent() }
//       .menuBarExtraStyle(.window)
// See MyAppMac/AGENTS.md and R2 V6 / R4 V23.
```
Gotchas:
- macOS targets need hardened runtime + App Sandbox (contracts §2); the App Group
  on macOS is `group.com.example.myapp` **without** a team prefix only if the
  entitlement is written that way consistently — keep the single string from
  contracts §1.
- `@NSApplicationDelegateAdaptor` is `@MainActor` in the SDK, and `NSApplicationDelegate`
  is `@MainActor`-annotated, so a delegate class needs no `nonisolated` (unlike the NSE).
- Universal Purchase requires the macOS bundle ID to equal the iOS one — contracts §2
  already does this.

---

### Group 11 — Swift Testing + XCUITest

**V25. Verified current shapes:**
```swift
@attached(peer) macro Test(_ displayName: String? = nil, _ traits: any TestTrait...)
@attached(peer) macro Test<C>(_ displayName: String?, _ traits: any TestTrait..., arguments: C)
@attached(peer) macro Suite(_ displayName: String? = nil, _ traits: any SuiteTrait...)
@freestanding(expression) macro expect(_ condition: Bool, _ comment: @autoclosure () -> Comment? = nil,
                                       sourceLocation: SourceLocation = #_sourceLocation)
func confirmation<R>(_ comment: Comment? = nil, expectedCount: …,
                     isolation: isolated (any Actor)? = #isolation,
                     sourceLocation: SourceLocation = #_sourceLocation,
                     _ body: (Confirmation) async throws -> sending R) async rethrows -> R
```
Swift Testing is `Swift 6.0 / Xcode 16.0`; `confirmation(…expectedCount:…)` with a
range is `Swift 6.1 / Xcode 16.3`. Traits we should actually use: `.tags(_:)`,
`.disabled(_:)`, `.enabled(if:)`, `.timeLimit(_:)`, `.serialized`, `.bug(_:)`.
Confidence: **high**.

**V26. Suites that touch `CheckpointStore` must be `@MainActor`, and the suite should
be a `struct` (fresh instance per test) — not a `class`.** Swift Testing creates a
new suite instance per test function, which is what makes `struct` suites the
idiom; `@MainActor` on the suite propagates to every `@Test` method so the
`@MainActor` store is reachable without `await`. Confidence: **high**.

**Crib — `Tests/MyAppTests/CheckpointStoreTests.swift`**
```swift
import Testing
import Foundation
@testable import MyApp

@MainActor
@Suite("CheckpointStore")
struct CheckpointStoreTests {
    private func makeStore() -> CheckpointStore {
        CheckpointStore(persistence: InMemoryCheckpointStore())
    }

    @Test("starting a session marks it active")
    func startSession() {
        let store = makeStore()
        #expect(store.session.isActive == false)
        store.startSession()
        #expect(store.session.isActive)
        #expect(store.session.startedAt != nil)
    }

    @Test("logging increments today's count", arguments: [1, 3, 7])
    func logCheckpoints(count: Int) throws {
        let store = makeStore()
        store.startSession()
        for i in 0..<count { store.logCheckpoint(note: "note \(i)") }
        #expect(store.todayCount == count)
        let last = try #require(store.checkpoints.last)
        #expect(last.note == "note \(count - 1)")
    }

    @Test("ending a session clears the start date")
    func endSession() {
        let store = makeStore()
        store.startSession()
        store.endSession()
        #expect(store.session.startedAt == nil)
    }
}

@Suite("WidgetSync")
struct WidgetSyncTests {
    @Test("round-trips a snapshot through the App Group")
    func roundTrip() throws {
        let snapshot = WidgetSnapshot(sessionStartedAt: Date(timeIntervalSince1970: 1_000),
                                      todayCount: 4,
                                      lastUpdatedAt: Date(timeIntervalSince1970: 2_000))
        WidgetSync.write(snapshot)
        let read = try #require(WidgetSync.read())
        #expect(read == snapshot)
    }
}
```

**V27. fastlane's upstream `SnapshotHelper.swift` is already `@MainActor`-annotated
and compiles under Swift 6 — no local patch needed.** Verified against
`fastlane/fastlane@master:snapshot/lib/assets/SnapshotHelper.swift`: the free
functions `setupSnapshot(_:waitForAnimations:)` and `snapshot(_:timeWaitingForIdle:)`
and `open class Snapshot: NSObject` all carry `@MainActor`. `XCUIApplication` is
`@MainActor class` in the SDK. Confidence: **high**.

**Crib — `Tests/MyAppUITests/LaunchAndScreenshotTests.swift`** (doubles as the
fastlane `snapshot` driver per ADR-0009 §5)
```swift
import XCTest

final class LaunchAndScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndCaptureScreenshots() {
        let app = XCUIApplication()
        setupSnapshot(app)                      // fastlane/SnapshotHelper.swift
        app.launchArguments += ["-uiTestMode", "1"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        snapshot("01_Home")

        let start = app.buttons["startSessionButton"]
        if start.waitForExistence(timeout: 5) {
            start.tap()
            snapshot("02_ActiveSession")
        }
    }
}
```
Gotchas:
- Mark UI-test methods `@MainActor` (or the whole class): `XCUIApplication` is
  `@MainActor`, and `XCTestCase` is not.
- `SnapshotHelper.swift` belongs to the **UI test target only**, added by
  `fastlane snapshot init`; keep it out of `project.yml`'s app sources.
- Accessibility identifiers (`startSessionButton`) are the contract between the app
  and the UI test — set them in the SwiftUI views, never rely on label text (it is
  localized).
- XCTest and Swift Testing coexist in one target; UI tests must stay XCTest
  (Swift Testing has no XCUI integration).

---

### Group 12 — Strict-concurrency review of contracts §4

**V28. `WidgetSync` (contracts §4.1) must be `nonisolated`, and `WidgetSnapshot`
should stay a `Sendable` struct.** The read side is called from inside a
`nonisolated` `TimelineProvider` and from the NSE; if MainActor-default isolation
makes `enum WidgetSync` main-actor isolated, every widget target fails to compile
with "call to main actor-isolated static method in a synchronous nonisolated
context". Spec delta D2. Confidence: **high**.

**V29. `CheckpointPersisting: Sendable` is not satisfiable by the `swiftdata`
component.** See V20. Spec delta D1. Confidence: **high**.

**V30. Everything else in contracts §4 is expressible cleanly.**
- §4.2 `SessionActivityAttributes` — `ActivityAttributes: Decodable, Encodable`
  with `associatedtype ContentState: Decodable, Encodable, Hashable`. Our shape
  satisfies it; adding `Sendable` to `ContentState` is free and correct (D3).
- §4.3 `SessionState` / `Checkpoint` — structs of `Sendable` members; the explicit
  `Sendable` annotation is redundant but harmless and self-documenting.
- §4.3 `@MainActor @Observable public final class CheckpointStore` — correct and
  idiomatic. `@Observable` + `@MainActor` compose; `@State private var store` in
  the `App` and `.environment(store)` / `@Environment(CheckpointStore.self)` in
  views is the current pattern (`@EnvironmentObject` is the `ObservableObject`
  legacy and must not appear).
- §4.4 intents — `@MainActor func perform() async` is legal (V14).
- §4.5 `Theme` — must be `nonisolated` (or plain static lets on an enum) because it
  is read from `nonisolated` timeline providers and from widget view bodies.
Confidence: **high**.

**V31. `@Observable` stores CANNOT be observed from extensions — different
processes.** Widgets, complications, the Live Activity extension and the NSE each
run in their own process with their own address space. contracts §4.1's App-Group
`UserDefaults` bridge is the only channel, and §4.1 already says so. No change
needed; recorded because the brief asks the question explicitly. The one nuance
worth documenting in `Shared/AGENTS.md`: `UserDefaults(suiteName:)` in an
App Group is *not* KVO-synchronised across processes — extensions read fresh on
each timeline invocation, which is exactly when they run, so this is fine; a host
app must re-read on foreground rather than trusting a cached value.
Confidence: **high**.

---

## Spec deltas

### D1 — `contracts.md` §4.3, `CheckpointPersisting` (from V20/V29)

Replace:
> ```swift
> public protocol CheckpointPersisting: Sendable {
>     func load() throws -> [Checkpoint]
>     func save(_ checkpoints: [Checkpoint]) throws
> }
> // Always-on impl: InMemoryCheckpointStore (+ UserDefaults-backed variant OK).
> // `swiftdata` component adds SwiftDataCheckpointStore + @Model mirror type.
> ```

with:
> ```swift
> @MainActor
> public protocol CheckpointPersisting {
>     func load() throws -> [Checkpoint]
>     func save(_ checkpoints: [Checkpoint]) throws
> }
> // Always-on impl: InMemoryCheckpointStore (+ UserDefaults-backed variant OK).
> // `swiftdata` component adds SwiftDataCheckpointStore + @Model mirror type.
> //
> // @MainActor, NOT Sendable: SwiftData's ModelContext is not Sendable and
> // ModelContainer.mainContext is @MainActor-isolated, so a Sendable protocol
> // could only be satisfied with @unchecked. CheckpointStore is @MainActor
> // anyway, so a main-actor protocol costs nothing and stays honest. (R4 V20)
> ```

### D2 — `contracts.md` §4.1, WidgetSync isolation (from V28)

Replace:
> ```swift
> public enum WidgetAppGroup {
> ```
> …
> ```swift
> public enum WidgetSync {
> ```

with:
> ```swift
> public nonisolated enum WidgetAppGroup {
> ```
> …
> ```swift
> public nonisolated enum WidgetSync {
> ```

and append to that subsection:
> All four types in this file (`WidgetAppGroup`, `WidgetSyncKey`,
> `WidgetSnapshot`, `WidgetSync`) are explicitly `nonisolated` because they are
> read from `nonisolated` `TimelineProvider` conformances and from the
> Notification Service Extension. Do not let `SWIFT_DEFAULT_ACTOR_ISOLATION`
> decide their isolation. (R4 V2/V28)

### D3 — `contracts.md` §4.2, Live Activity attributes (from V30)

Replace:
> ```swift
> public struct SessionActivityAttributes: ActivityAttributes {
>     public struct ContentState: Codable, Hashable {
> ```

with:
> ```swift
> public nonisolated struct SessionActivityAttributes: ActivityAttributes {
>     public struct ContentState: Codable, Hashable, Sendable {
> ```

### D4 — `contracts.md` §4, new preamble sentence (from V2)

Insert immediately after the `## 4. Cross-target Swift contracts` heading:
> **Isolation is explicit everywhere in this template.** Every type carries either
> `@MainActor` or `nonisolated`; nothing relies on `SWIFT_DEFAULT_ACTOR_ISOLATION`.
> This keeps the sources compiling identically under Xcode 26's new-project
> default (`MainActor`) and the legacy default (`nonisolated`). The types that
> MUST be `nonisolated`: every `TimelineProvider` conformance, the
> `UNNotificationServiceExtension` subclass, the `WCSessionDelegate` conformance,
> `Shared/Sync/WidgetSync.swift`'s types, `SessionActivityAttributes`, and
> `Shared/Theme/Theme.swift`. (R4 V2)

### D5 — `contracts.md` §4.4, App Intents (from V11/V12/V13)

Replace:
> `StartSessionIntent`, `EndSessionIntent`, `LogCheckpointIntent` +
> `MyAppShortcuts: AppShortcutsProvider`. All route through `CheckpointStore`.

with:
> `StartSessionIntent`, `EndSessionIntent`, `LogCheckpointIntent` +
> `MyAppShortcuts: AppShortcutsProvider`. All route through `CheckpointStore`.
> Metadata uses `static let` (never `static var` — Swift 6 rejects stored static
> vars); `perform()` is `@MainActor func perform() async throws -> some IntentResult & ProvidesDialog`.
> `openAppWhenRun` is used at the iOS 18 floor and is deprecated at iOS 26 in
> favour of `supportedModes: IntentModes` — carry the migration comment.
> Every `AppShortcut` phrase must contain the `\(.applicationName)` token, and
> `shortTitle:` + `systemImageName:` are non-optional. (R4 V11–V14)

### D6 — `contracts.md` §2, add a rule to the "Rules baked in" list (from V9)

Append:
> - `WidgetFamily.accessoryCorner` is watchOS-only and
>   `WidgetFamily.systemExtraLargePortrait` is iOS 27 **beta** — neither may appear
>   in an iOS/macOS `supportedFamilies` array on the Xcode 26 SDK. (R4 V9)
> - Every widget/complication view MUST call `.containerBackground(_:for: .widget)`
>   or the system renders an "adopt containerBackground" placeholder instead of the
>   widget. (R4 V8)

### D7 — `docs/adr/0009-walking-skeleton-and-gates.md`, Consequences (from V1)

Append a bullet:
> - Pennywise is a Swift **5.10** codebase on every target. It is the reference for
>   API shape, target/entitlement/plist wiring and product behaviour — **not** for
>   Swift 6 concurrency. Three of its patterns (WCSession delegate hops,
>   `static var` App Intent metadata, unannotated `TimelineProvider` structs) are
>   compile errors under our settings. (R4 V1)

### D8 — `docs/adr/0004-v1-component-menu.md`, Consequences (from V16)

Append a bullet:
> - The `store` stub is API-driven (`Product.products` / `purchase` /
>   `Transaction.updates` / `Transaction.currentEntitlements`), not
>   `SubscriptionStoreView`. SwiftUI's merchandising views need a real App Store
>   Connect subscription group and render a failure state against the template's
>   placeholder identifiers; they are documented as the production upgrade path.
>   (R4 V16)

---

## Capability audit (ADR-0006 decision-10)

Native capabilities in R4's domain that the current design under-uses, and things
we plan to hand-roll that a framework already does.

**A1 — WidgetKit push (`WidgetPushHandler` / `.pushHandler(_:)`, iOS 26+) is the
native replacement for half of what the `nse` component exists to do.**
`WidgetPushInfo` (iOS 26.0) carries a widget push token; `WidgetCenter.shared.currentPushInfo`
and `func pushHandler(_ pushHandlerType: any WidgetPushHandler.Type) -> some WidgetConfiguration`
(iOS 26.0) let a *widget extension* register its own APNs token and be refreshed by
`apns-push-type: widgets` with `{"aps":{"content-changed":true}}` — no host app, no
NSE, no App-Group mirror hop [S16][S17]. At our iOS 18 floor we cannot adopt it, but
the `nse` component's `AGENTS.md` must say "on an iOS 26 floor, delete this and use
`WidgetPushHandler`", or the template will teach the workaround forever.
**Action: documentation-only in v1.**

**A2 — `.supplementalActivityFamilies([.small])` (iOS 18) is free watch support we
are not taking.** Our `live-activity` + `watch` components currently duplicate
effort: the watch renders its own view from the App-Group snapshot, when iOS 18+
will project the Live Activity onto the paired watch for one modifier. **Action:
add the modifier to `ActivityConfiguration` (V6) and note the interaction in
`docs/`.**

**A3 — App Intents' native DI (`AppDependencyManager` + `@Dependency`) instead of a
singleton or a hand-rolled App-Group command queue.** Pennywise hand-rolls
`WidgetSync.queueTrackingCommand("start")` + `drainPendingTrackingCommand()` — a
bespoke IPC queue — because its intents are open-app. `AppDependencyManager.shared.add(dependency:)`
registered in `MyAppApp.init()` plus `@Dependency var store: CheckpointStore` in the
intent is the framework's answer for in-process intents, and it is exactly our
shape (contracts §4.4 says intents route through `CheckpointStore`).
**Action: use `@Dependency`; do not port Pennywise's command queue.**

**A4 — Interactive widgets: `Button(intent:)` / `Toggle(isOn:intent:)` (iOS 17+,
`nonisolated init<I>(intent: I, …) where I: AppIntent`).** We already build three
App Intents; wiring `Button(intent: StartSessionIntent())` into the
`systemSmall`/`systemMedium` widget costs ~4 lines and demonstrates the single most
asked-about WidgetKit feature. Currently our widgets are render-only.
**Action: add one interactive button to the home widget.**

**A5 — `ControlWidget` + `ControlWidgetButton` (iOS 18, macOS 26, watchOS 26) —
Control Center / Lock Screen / Action Button surface.** `@MainActor protocol ControlWidget`
is available at our iOS 18 floor and is the natural home for "start a session"
given we already have the intent. It is *not* in the ADR-0004 v1 component menu.
**Action: propose `controls` as a v1.1 component; do not scope-creep v1** — but
record it so the omission is a decision, not an oversight.

**A6 — `Activity.pushToStartToken` / `pushToStartTokenUpdates` (static, no running
activity required).** Our `live-activity` push registrar stub is marker-gated on
`nse` and observes `activity.pushTokenUpdates` only, which cannot start an activity
remotely. The static pair is the documented "start from push" path.
**Action: include both in the registrar stub so the seam is complete.**

**A7 — `PushType.channel(String)` (broadcast Live Activity updates).** New alongside
`.token`; lets one APNs channel fan out to every subscriber's activity without
per-device tokens. Irrelevant to a single-user template, but the registrar stub
should name it in a comment so nobody re-invents fan-out.

**A8 — `HKStatisticsQueryDescriptor` instead of fetching samples and summing.**
Our `health` stub reads one sample; any real consumer wants "today's total", which
HealthKit computes server-side. **Action: mention it in the `health` AGENTS.md.**

**A9 — `ModelConfiguration(groupContainer:)` instead of a hand-rolled shared file
URL.** Already used in the crib (V20); calling it out because the common
anti-pattern is `ModelConfiguration(url: appGroupURL.appending(...))`, which
bypasses SwiftData's own App-Group handling.

**A10 — Swift Testing traits we should use rather than re-implement:**
`@Test(arguments:)` (parameterisation — replaces hand-written loops),
`.timeLimit(_:)` (replaces manual timeouts), `.serialized` (replaces bespoke
locking in suites that touch `UserDefaults`), `#require` (replaces
`guard … else { Issue.record() }`), and `confirmation(expectedCount:)` (replaces
`XCTestExpectation`). Our test cribs use all five.

**A11 — `#Preview(as:widget:timeline:)` and `#Preview(as:using:widget:contentStates:)`
instead of a hand-rolled preview harness.** WidgetKit ships first-class preview
macros for both widgets and Live Activities; there is no reason for the template to
contain a `WidgetPreviewContext` shim.

**A12 — `xcodebuild -destination 'generic/platform=iOS Simulator'` (R2 V4) removes
the need for named devices in the crib-sheet build commands.** Cross-referenced
here because R4's snippets are validated by `make build*`, not by `make test`.

**Under-use we are deliberately accepting (recorded, not actioned):**
`AppIntentTimelineProvider` + `WidgetConfigurationIntent` (no configuration surface
in the Checkpoints domain — V7); `SubscriptionStoreView`/`StoreView`/`ProductView`
(need real ASC products — V16); `MenuBarExtra` (platform hazard — V23);
`@ModelActor` background contexts (single-writer main-actor design — V20);
`Activity.request(…style: .transient)` (no transient-activity use case).

---

## Sources

All Apple declarations were read from the documentation JSON API on **2026-08-02**
via `https://developer.apple.com/tutorials/data/documentation/<path>.json`
(the same payload that renders developer.apple.com; the HTML pages are
JS-rendered and unfetchable). Paths quoted below are the `<path>` component.

- [S1] ActivityKit — `activitykit/activity`, `activitykit/activitycontent`,
  `activitykit/pushtype`, `activitykit/activitystyle`,
  `activitykit/activityuidismissalpolicy`, `activitykit/activityattributes`,
  `activitykit/activityauthorizationinfo`, `widgetkit/activityconfiguration`,
  `widgetkit/dynamicisland`, `widgetkit/dynamicislandexpandedregion`,
  `widgetkit/activityfamily`, `widgetkit/activitypreviewviewkind`,
  `swiftui/widgetconfiguration/supplementalactivityfamilies(_:)`,
  `swiftui/view/activitybackgroundtint(_:)`. Fetched 2026-08-02.
- [S2] WidgetKit — `widgetkit/timelineprovider`, `widgetkit/appintenttimelineprovider`,
  `widgetkit/staticconfiguration`, `widgetkit/appintentconfiguration`,
  `widgetkit/widgetfamily` (+ per-case `accessorycorner`, `accessoryinline`,
  `systemextralargeportrait`), `swiftui/widget`, `swiftui/widgetbundle`,
  `widgetkit/widgetcenter`, `widgetkit/preview-macros`,
  `swiftui/view/containerbackground(_:for:)`, `swiftui/containerbackgroundplacement`,
  `swiftui/controlwidget`, `widgetkit/controlwidgetbutton`. Fetched 2026-08-02.
- [S3] App Intents — `appintents/appintent` (topics incl. the Deprecated section),
  `appintents/appintent/title`, `appintents/appintent/openappwhenrun` (raw JSON
  `platforms` array showing `deprecatedAt: 26.0`, `message: "Please provide
  'supportedModes' instead"`), `appintents/intentmodes`, `appintents/appshortcut`,
  `appintents/appshortcutsprovider`, `appintents/intentresult`,
  `appintents/providesdialog`, `appintents/intentdescription`,
  `appintents/appdependencymanager`, `foundation/localizedstringresource`
  (Sendable conformance), `swiftui/button/init(intent:label:)`,
  `swiftui/toggle/init(ison:intent:label:)`. Fetched 2026-08-02.
- [S4] Antoine van der Lee, "Default Actor Isolation in Swift 6.2", SwiftLee —
  https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/
  (retrieved 2026-08-02).
- [S5] fatbobman, "Default Actor Isolation — New Problems from Good Intentions" —
  https://fatbobman.com/en/posts/default-actor-isolation/ (retrieved 2026-08-02);
  documents `nonisolated` before a type declaration as the fix for Xcode 26
  template code.
- [S6] Apple Developer Forums thread 806619, "Subclassing NSMenuItem gives error in
  Xcode 26.1" — https://developer.apple.com/forums/thread/806619 (retrieved
  2026-08-02); exact error text `Main actor-isolated initializer … has different
  actor isolation from nonisolated overridden declaration`.
- [S7] swiftlang/swift issue 78518, "'cannot be used to satisfy nonisolated protocol
  requirement' diagnostic should identify protocol" —
  https://github.com/swiftlang/swift/issues/78518 (retrieved 2026-08-02).
- [S8] pointfreeco/swift-dependencies discussion 310, "Main actor-isolated static
  property 'liveValue' cannot be used to satisfy nonisolated protocol requirement;
  this is an error in the Swift 6 language mode" —
  https://github.com/pointfreeco/swift-dependencies/discussions/310 (retrieved
  2026-08-02).
- [S9] Lee Kah Seng, "Understanding Container Background for Widget in iOS 17",
  Swift Senpai — https://swiftsenpai.com/development/widget-container-background/
  (retrieved 2026-08-02).
- [S10] Filip Němeček, "Hotfixing widgets for iOS 17: containerBackground + padding" —
  https://nemecek.be/blog/192/hotfixing-widgets-for-ios-17-containerbackground-padding
  (retrieved 2026-08-02).
- [S11] Scott Berrevoets, "Managing code deprecations on iOS", 2025-08-20 —
  https://www.scottberrevoets.com/2025/08/20/managing-code-deprecations-on-ios/
  (retrieved 2026-08-02).
- [S12] NSHipster, "Swift API Availability" — https://nshipster.com/available/
  (retrieved 2026-08-02).
- [S13] steipete/CodexBar issue 802, "Menu bar icon never registers on macOS 26.4 —
  RenderBox failure" — https://github.com/steipete/CodexBar/issues/802 (retrieved
  2026-08-02).
- [S14] p0deje/Maccy issue 1224, "menubar icon missing in macOS 26.0.1 Tahoe" —
  https://github.com/p0deje/Maccy/issues/1224 (retrieved 2026-08-02).
- [S15] AppAddict, "Mac Menu Bar Chaos" — https://appaddict.app/post/mac-menu-bar-chaos
  (retrieved 2026-08-02).
- [S16] Apple, "Updating widgets with WidgetKit push notifications" —
  https://developer.apple.com/documentation/WidgetKit/Updating-widgets-with-widgetkit-push-notifications
  (retrieved 2026-08-02); plus `widgetkit/widgetpushhandler`,
  `widgetkit/widgetpushinfo`, `swiftui/widgetconfiguration/pushhandler(_:)` JSON.
- [S17] Apple, "What's new in widgets", WWDC25 session 278 —
  https://developer.apple.com/videos/play/wwdc2025/278/ (retrieved 2026-08-02).
- [S18] StoreKit — `storekit/product`, `storekit/transaction`,
  `storekit/verificationresult`, `storekit/product/purchaseresult`,
  `storekit/product/purchase(options:)`, `storekit/subscriptionstoreview`,
  `storekit/storeview`, `storekit/productview`. Fetched 2026-08-02.
- [S19] SwiftData — `swiftdata/modelcontainer` (+ relationships showing `Sendable`),
  `swiftdata/modelcontext` (relationships showing NO `Sendable`),
  `swiftdata/modelconfiguration`, `swiftdata/persistentmodel`, `swiftdata/model()`,
  `swiftdata/modelactor()`, `swiftdata/query`,
  `swiftui/scene/modelcontainer(for:inmemory:isautosaveenabled:isundoenabled:onsetup:)`.
  Fetched 2026-08-02.
- [S20] WatchConnectivity — `watchconnectivity/wcsession` (relationships: no
  `Sendable`), `watchconnectivity/wcsessiondelegate` (full requirement list).
  Fetched 2026-08-02.
- [S21] UserNotifications / HealthKit / AuthenticationServices / CloudKit /
  ServiceManagement / SwiftUI —
  `usernotifications/unnotificationserviceextension` (+ both overrides),
  `healthkit/hkhealthstore`, `healthkit/hkhealthstore/requestauthorization(toshare:read:)`,
  `healthkit/hksamplequerydescriptor`, `healthkit/hkstatisticsquerydescriptor`,
  `authenticationservices/signinwithapplebutton`,
  `authenticationservices/asauthorizationappleidprovider/getcredentialstate(foruserid:completion:)`
  (async sibling in the same payload), `cloudkit/ckcontainer/accountstatus(completionhandler:)`,
  `cloudkit/ckaccountstatus`, `servicemanagement/smappservice`, `swiftui/menubarextra`,
  `swiftui/settings`, `swiftui/app`, `swiftui/uiapplicationdelegateadaptor`,
  `swiftui/preview(_:body:)`, `observation/observable()`. Fetched 2026-08-02.
- [S22] Swift Testing — `testing` (framework topics), `testing/test(_:_:)`,
  `testing/suite(_:_:)`, `testing/expect(_:_:sourcelocation:)`,
  `testing/confirmation(_:expectedcount:isolation:sourcelocation:_:)`,
  `testing/traits`. Fetched 2026-08-02.
- [S23] fastlane `SnapshotHelper.swift`, master branch —
  https://raw.githubusercontent.com/fastlane/fastlane/master/snapshot/lib/assets/SnapshotHelper.swift
  (retrieved 2026-08-02); `@MainActor` on the free functions and on
  `open class Snapshot: NSObject`.
- [S24] Reference repo (read-only), `/home/user/pennywise-apple-universal`:
  `project.yml` (SWIFT_VERSION 5.10 × 8 targets; extension plist keys),
  `Shared/WatchSync.swift`, `Shared/Support/WatchLink.swift`,
  `Pennywise/Services/LiveActivityManager.swift`,
  `PennywiseLiveActivity/PennywiseLiveActivityWidget.swift`,
  `PennywiseHomeWidget/PennywiseHomeWidget.swift`,
  `PennywiseNotificationService/NotificationService.swift`,
  `Pennywise/Intents/PennywiseTrackingIntents.swift`,
  `PennywiseMac/PennywiseMacApp.swift`, `PennywiseMac/Services/MacAppDelegate.swift`.
  Inspected 2026-08-02.
- [S25] Sibling research: `specs/_build/research/R2-toolchain.md` (V1, V2b, V4, V6,
  V7) — toolchain pins, Xcode 26 concurrency defaults, runner devices, MenuBarExtra
  finding, OS-27 API deltas.
