import SwiftUI

@MainActor
struct MacRootView: View {
    /// Sidebar bounds, not design tokens: the controls column has to fit the
    /// elapsed timer at `Theme.font.title` without wrapping.
    private static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (220, 260, 320)

    var body: some View {
        NavigationSplitView {
            MacSessionControls()
                .navigationSplitViewColumnWidth(
                    min: Self.sidebarWidth.min,
                    ideal: Self.sidebarWidth.ideal,
                    max: Self.sidebarWidth.max
                )
        } detail: {
            MacCheckpointList()
        }
        .navigationTitle("MyApp")
    }
}

@MainActor
struct MacSettingsView: View {
    /// Standard macOS preferences-pane width; nothing here is design-token shaped.
    private static let paneWidth: CGFloat = 460

    @Environment(CheckpointStore.self) private var store

    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginItemError = nil
                        } catch {
                            // Approval can be pending in System Settings, so the
                            // toggle must follow the service, not the click.
                            launchesAtLogin = LoginItem.isEnabled
                            loginItemError = error.localizedDescription
                        }
                    }

                if let loginItemError {
                    Text(loginItemError)
                        .font(Theme.font.caption)
                        .foregroundStyle(Theme.color.danger)
                }
            }

            Section("Session") {
                LabeledContent("Checkpoints today", value: "\(store.todayCount)")
                LabeledContent("Checkpoints stored", value: "\(store.checkpoints.count)")
            }

            // @template:store BEGIN
            Section("Pro") {
                PaywallView()
            }
            // @template:store END

            // @template:account BEGIN
            Section("Account") {
                SignInView()
            }
            // @template:account END
        }
        .formStyle(.grouped)
        .frame(width: Self.paneWidth)
        .padding(Theme.spacing.medium)
    }
}

#Preview {
    MacRootView()
        .environment(CheckpointStore(persistence: InMemoryCheckpointStore()))
}
