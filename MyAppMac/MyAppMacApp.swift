import ServiceManagement
import SwiftUI

@main
@MainActor
struct MyAppMacApp: App {
    /// Window floor rather than a design token: below this the split view
    /// collapses and the checkpoint table loses its second column.
    private static let minimumWindowSize = CGSize(width: 640, height: 420)

    @State private var store = CheckpointStore(persistence: InMemoryCheckpointStore())

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MacRootView()
                .environment(store)
                .frame(
                    minWidth: Self.minimumWindowSize.width,
                    minHeight: Self.minimumWindowSize.height
                )
        }
        .windowResizability(.contentMinSize)

        Settings {
            MacSettingsView()
                .environment(store)
        }
    }
}

// HAZARD: this app ships no menu-bar surface on purpose (ADR-0009). The
// macOS 26 menu-bar layer regressed for both MenuBarExtra and NSStatusItem —
// see docs/template-guide.md before adding one.

/// Login item. macOS 13+, and every call must stay on the main actor.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
