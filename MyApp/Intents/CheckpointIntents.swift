import AppIntents
import Foundation

// Intent metadata is `static let`, never `static var`: a stored static var is
// nonisolated global mutable state and Swift 6 rejects it. The types are
// `@MainActor`, never `nonisolated`: `@Parameter` and `@Dependency` are
// mutable stored properties, and a type-level `nonisolated` distributes onto
// them — "'nonisolated' cannot be applied to mutable stored properties". The
// nonisolated protocol requirements are still satisfied: an immutable
// Sendable `static let` reads across isolation, and `perform()` is an async
// requirement, so a main-actor witness is legal.

@MainActor
struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Session"
    static let description = IntentDescription("Start a MyApp session.")
    // Deprecated at iOS 26 in favour of `supportedModes: IntentModes`; at the
    // iOS 18 floor it is warning-free. Raise the floor, then swap it.
    static let openAppWhenRun = true

    @Dependency private var store: CheckpointStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        store.startSession()
        return .result(dialog: "Session started.")
    }
}

@MainActor
struct LogCheckpointIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Checkpoint"
    static let description = IntentDescription("Log a checkpoint in the current MyApp session.")
    static let openAppWhenRun = false

    @Parameter(title: "Note", requestValueDialog: "What should the note say?")
    var note: String?

    @Dependency private var store: CheckpointStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let checkpoint = store.logCheckpoint(note: note)
        let time = checkpoint.timestamp.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Logged checkpoint at \(time).")
    }
}

@MainActor
struct EndSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Session"
    static let description = IntentDescription("End the current MyApp session.")
    static let openAppWhenRun = false

    @Dependency private var store: CheckpointStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        store.endSession()
        return .result(dialog: "Session ended.")
    }
}

/// Must live in the app target, not an extension, or the shortcuts never
/// register. Every phrase carries `\(.applicationName)` — App Intents fails
/// validation on a phrase without it. `@MainActor` because the builder
/// constructs the intents above, whose initializers are main-actor isolated.
@MainActor
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
            phrases: [
                "End my \(.applicationName) session",
            ],
            shortTitle: "End Session",
            systemImageName: "stop.fill"
        )
    }
}
