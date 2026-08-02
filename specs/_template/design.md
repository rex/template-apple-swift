# Design — <feature-slug>

> How we will satisfy `spec.md`. Reference the spec by section in every
> decision. Freeze the type contracts in Phase 1 and stop re-litigating them.

## Architecture overview

```
<ascii diagram: views → store → persistence, plus any extension process>
```

Which process does what matters more than which file does what: the app, each
extension, and the watch app are separate processes that share only the App
Group container and (for watch) WCSession.

## Types

### <Type 1>

- **Responsibility**: <one sentence>
- **Isolation**: `@MainActor` / `nonisolated` — and why
- **Sendable**: yes / no — and why
- **Lives in**: `Shared/<area>/<File>.swift` or `<Target>/<area>/<File>.swift`
- **Satisfies**: spec.md §<N>

### <Type 2>

- ...

## Contracts (freeze in Phase 1)

```swift
// Signatures only — no bodies. Once merged these are frozen for the rest of
// the feature; extend with new members rather than changing these.

@MainActor
public protocol <Name> {
    func <method>(_ value: <Type>) throws -> <Result>
}

public struct <Name>: Codable, Equatable, Sendable {
    public var <field>: <Type>
}
```

## State + persistence

- Mutation path: everything goes through `CheckpointStore`. If this feature
  needs a second store, say why here — a second mutation path is an ADR.
- Persistence: `CheckpointPersisting` implementation affected? SwiftData model
  changes? A `@Model` change is a migration question, answer it here.
- Cross-process: what is written to `WidgetSync`, by whom, and when. Widgets
  and complications are read-only.

## UI

- Screens / views added or changed, and which `Theme` tokens they use.
- New user-facing strings → String Catalog keys (no literals in views).
- Accessibility: labels, Dynamic Type behavior, VoiceOver order.

## Extension impact

| Extension | Change | Entitlement / plist consequence |
|---|---|---|
| `HomeWidget` | <new family? new timeline entry?> | |
| `LiveActivity` | <ContentState fields added?> | ContentState must stay in lockstep with the writer |
| `NotificationService` | <payload shape?> | |
| `WatchComplications` | <families?> | |

Remember: an extension's bundle ID is its host's ID plus exactly one segment,
and every widget view calls `.containerBackground(_:for: .widget)`.

## project.yml impact

- New target? → new `xcodegen/components/<id>.yml`, a `components.yaml` entry,
  and an `include:` line with `relativePaths: false`.
- New source directory? → exactly one file may declare it.
- New entitlement or Info.plist key? → the component's include fragment owns
  it, so pruning the component removes the key.
- Nothing here writes `DEVELOPMENT_TEAM`, `MARKETING_VERSION` or
  `CURRENT_PROJECT_VERSION` — those live only in `Config/*.xcconfig`.

## Concurrency plan

- What crosses an isolation boundary, and how (`await`, `Sendable` value,
  `AsyncStream`).
- Anything that must NOT be main-actor and why (timeline providers, delegates,
  extension entry points).
- No new `@unchecked Sendable` without a justification written here.

## Error handling

| Condition | Behavior | Where |
|---|---|---|
| <condition> | <user-visible result> | `<File>.swift` |

## Observability

- `os.Logger` subsystem + category for the new code.
- MetricKit signals worth watching after release.
- What must never be logged (tokens, health data, full payloads).

## Testing strategy

- Swift Testing units: which behaviors, which suites.
- What needs a UI test instead, and why the unit test cannot cover it.
- Anything untestable without a device — say so explicitly rather than
  pretending the simulator covers it.

## Alternatives considered

### Alternative 1

- **Why considered**: <context>
- **Why rejected**: <reason>
- **Trade-off accepted**: <what we give up>

## Open design questions

- (none yet)
