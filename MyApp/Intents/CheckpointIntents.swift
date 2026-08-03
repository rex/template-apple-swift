import AppIntents
import Foundation

// The one file where Swift 6.2-era isolation and a pre-concurrency framework
// contract collide, adjudicated by real compiler verdicts:
//
// - Types are `@MainActor`, never `nonisolated`: a type-level `nonisolated`
//   distributes onto `@Parameter`/`@Dependency`, which are MUTABLE STORED
//   properties — "'nonisolated' cannot be applied to mutable stored
//   properties".
// - The conformances can never be isolated: `AppIntent` and
//   `AppShortcutsProvider` inherit `Sendable`, so their metatypes are
//   `SendableMetatype`, and SE-0470 forbids (and never infers) an isolated
//   conformance — "conformance … crosses into main actor-isolated code".
// - Therefore every SYNCHRONOUS witness is explicitly `nonisolated`: the
//   hand-written `init()` (the synthesized one would be main-actor isolated),
//   the `static let` metadata (immutable + Sendable, so this is free), and
//   `appShortcuts`. `perform()` is the single isolated member the conformance
//   tolerates, because that requirement is `async`.

@MainActor
struct StartSessionIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Start Session"
    nonisolated static let description = IntentDescription("Start a MyApp session.")
    // Deprecated at iOS 26 in favour of `supportedModes: IntentModes`; at the
    // iOS 18 floor it is warning-free. Raise the floor, then swap it.
    nonisolated static let openAppWhenRun = true

    @Dependency private var store: CheckpointStore

    /// `AppIntent` requires a synchronous `init()`, and an isolated witness is
    /// illegal here. The wrapper storage self-initializes, so the body is empty.
    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        store.startSession()
        return .result(dialog: "Session started.")
    }
}

@MainActor
struct LogCheckpointIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Log Checkpoint"
    nonisolated static let description = IntentDescription("Log a checkpoint in the current MyApp session.")
    nonisolated static let openAppWhenRun = false

    @Parameter(title: "Note", requestValueDialog: "What should the note say?")
    var note: String?

    @Dependency private var store: CheckpointStore

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let checkpoint = store.logCheckpoint(note: note)
        let time = checkpoint.timestamp.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Logged checkpoint at \(time).")
    }
}

@MainActor
struct EndSessionIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "End Session"
    nonisolated static let description = IntentDescription("End the current MyApp session.")
    nonisolated static let openAppWhenRun = false

    @Dependency private var store: CheckpointStore

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        store.endSession()
        return .result(dialog: "Session ended.")
    }
}

/// Must live in the app target, not an extension, or the shortcuts never
/// register. Every phrase carries `\(.applicationName)` — App Intents fails
/// validation on a phrase without it. The getter is `nonisolated` (the
/// requirement is synchronous and the conformance cannot be isolated); it
/// only constructs the intents above through their nonisolated `init()`s.
@MainActor
struct MyAppShortcuts: AppShortcutsProvider {
    nonisolated static var appShortcuts: [AppShortcut] {
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
            phrases: [
                "End my \(.applicationName) session",
            ],
            shortTitle: "End Session",
            systemImageName: "stop.fill"
        )
    }
}
