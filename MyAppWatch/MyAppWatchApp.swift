import SwiftUI

@main
@MainActor
struct MyAppWatchApp: App {
    /// The watch keeps its own store rather than mirroring the phone's writes
    /// blindly: every mutation here also writes the App Group snapshot, which
    /// is what feeds the complications in this same bundle.
    @State private var store = CheckpointStore(persistence: InMemoryCheckpointStore())

    init() {
        Theme.registerFonts()
        // Touching the shared link at launch activates WCSession before any
        // view asks whether the phone is reachable.
        _ = WatchLink.shared
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(store)
        }
    }
}
