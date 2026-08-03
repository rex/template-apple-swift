# Spec — <feature-slug>

> Requirements in EARS notation (Easy Approach to Requirements Syntax).
> This file is the canonical source of truth. `design.md`, `plan.md` and
> `tasks.md` derive from it. When they drift, fix the plan, not the spec.

## Summary

<2–4 sentences. What is being built and why. Link to the ticket or radar.>

## Goals

- <user-visible goal 1>
- <user-visible goal 2>

## Non-goals

- <what this feature explicitly does NOT do>
- <adjacent scope we are deferring>

## Surfaces touched

Name every target the feature reaches. Anything not listed is out of scope,
and any extension listed pulls in its own entitlement + Info.plist work.

| Surface | Touched? | Note |
|---|---|---|
| `MyApp` (iOS) | yes / no | |
| `MyAppMac` (macOS) | yes / no | |
| `MyAppWatch` (watchOS) | yes / no | |
| `HomeWidget` / `MacWidget` | yes / no | widgets read `WidgetSync`, never write |
| `LiveActivity` | yes / no | `NSSupportsLiveActivities` lives in the HOST plist |
| `WatchComplications` | yes / no | `accessoryCorner` is watchOS-only |
| `NotificationService` | yes / no | needs `aps-environment` on the host |
| App Intents / Shortcuts | yes / no | phrases must contain `\(.applicationName)` |

## Acceptance criteria (EARS notation)

Prefer `when` / `while` / `if` / `where` over freeform prose.

### Ubiquitous (always true)

- The app shall <behavior>.
- Every type introduced by this feature shall declare `@MainActor` or
  `nonisolated` explicitly.

### Event-driven (`when`)

- When the user taps Start, the app shall begin a session and write the new
  snapshot through `WidgetSync` before the next run loop.
- When a checkpoint is logged, the Live Activity shall update within 1 second.

### State-driven (`while`)

- While a session is active, the Watch complication shall show elapsed time.
- While the App Group container is unreadable, the widget shall render the
  last known snapshot rather than an error state.

### Unwanted behavior (`if` / `then`)

- If HealthKit authorization is denied, then the app shall continue with the
  feature hidden and shall not prompt again in the same launch.
- If a WCSession payload exceeds the transport limit, then the app shall send
  a summary instead of failing the transfer.

### Optional / component-gated (`where`)

- Where the `live-activity` component is enabled, the app shall start an
  Activity when a session begins.
- Where the `swiftdata` component is disabled, the app shall persist through
  the in-memory store with no behavioral difference to the UI.

## Platform floors

State any API this feature needs that is above the repo floors
(iOS 18.0 · macOS 15.0 · watchOS 11.0). Raising a floor is an ADR, not a
spec decision.

- <API> requires <OS version> — <in-floor / needs availability check / needs ADR>

## Privacy + entitlements

- New entitlements: <none / list>
- New usage-description strings: <none / list>
- `PrivacyInfo.xcprivacy` changes: <none / which API types + reason codes>

## Success metrics

- <metric 1 — how we know it works>
- <MetricKit signal, crash-free rate, or user-visible outcome>

## Open questions

- (none yet)

## References

- Ticket: <link>
- Related ADRs: <ADR-NNNN>
- Skill reference: `lang-swift-apple/references/<file>.md`
