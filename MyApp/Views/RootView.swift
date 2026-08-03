import SwiftUI

@MainActor
struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "flag.checkered") }

            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.color.accent)
    }
}

#Preview {
    RootView()
        .environment(CheckpointStore(persistence: InMemoryCheckpointStore()))
}
