import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(CheckpointStore.self) private var store

    // @template:health BEGIN
    @State private var health = HealthService()
    @State private var isHealthEnabled = false
    // @template:health END

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("Version", value: AppInfo.current.versionLabel)
                    LabeledContent("Build", value: AppInfo.current.buildLabel)
                    if let provenance = AppInfo.current.provenanceLabel {
                        LabeledContent("Source", value: provenance)
                    }
                }

                Section("Session") {
                    LabeledContent("Checkpoints today", value: "\(store.todayCount)")
                    LabeledContent("Checkpoints stored", value: "\(store.checkpoints.count)")
                }

                // @template:store BEGIN
                Section("Pro") {
                    NavigationLink("Upgrade") {
                        PaywallView()
                    }
                }
                // @template:store END

                // @template:account BEGIN
                Section("Account") {
                    NavigationLink("Sign in") {
                        SignInView()
                    }
                }
                // @template:account END

                // @template:health BEGIN
                Section("Health") {
                    Toggle("Read Health samples", isOn: $isHealthEnabled)
                        .font(Theme.font.body)
                }
                .onChange(of: isHealthEnabled) { _, enabled in
                    guard enabled else { return }
                    Task { try? await health.requestAuthorization() }
                }
                // @template:health END
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(CheckpointStore(persistence: InMemoryCheckpointStore()))
}
