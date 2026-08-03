import SwiftUI

@MainActor
struct WatchHomeView: View {
    @Environment(CheckpointStore.self) private var store

    private static let maxSessionSeconds: TimeInterval = 24 * 60 * 60

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacing.small) {
                    elapsed
                    counts
                    sessionButton
                    logButton
                    phoneStatus
                }
                .padding(.horizontal, Theme.spacing.xs)
            }
            .navigationTitle("MyApp")
        }
    }

    private var elapsed: some View {
        Group {
            if let startedAt = store.session.startedAt {
                Text(
                    timerInterval: startedAt...startedAt.addingTimeInterval(Self.maxSessionSeconds),
                    countsDown: false
                )
                .monospacedDigit()
            } else {
                Text("—")
            }
        }
        .font(Theme.font.title)
        .foregroundStyle(Theme.color.foreground)
    }

    private var counts: some View {
        Text("\(store.todayCount) today")
            .font(Theme.font.caption)
            .foregroundStyle(Theme.color.muted)
    }

    private var sessionButton: some View {
        Button {
            if store.session.isActive {
                store.endSession()
            } else {
                store.startSession()
            }
            mirrorToPhone()
        } label: {
            Label(
                store.session.isActive ? "Stop" : "Start",
                systemImage: store.session.isActive ? "stop.fill" : "play.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(store.session.isActive ? Theme.color.danger : Theme.color.accent)
    }

    private var logButton: some View {
        Button {
            store.logCheckpoint(note: nil)
            mirrorToPhone()
        } label: {
            Label("Log", systemImage: "flag.checkered")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!store.session.isActive)
    }

    /// The inbound half of the mirror. Latest-state-wins, so the phone's number
    /// is shown alongside the watch's rather than overwriting it — reconciling
    /// two writers is an app decision, not a template one.
    private var phoneStatus: some View {
        VStack(spacing: Theme.spacing.xxs) {
            if let payload = WatchLink.shared.lastPayload {
                Text("Phone: \(payload.todayCount) today")
            } else {
                Text(WatchLink.shared.isReachable ? "Phone reachable" : "Phone not reachable")
            }
        }
        .font(Theme.font.caption)
        .foregroundStyle(Theme.color.muted)
        .padding(.top, Theme.spacing.small)
    }

    private func mirrorToPhone() {
        let payload = WatchPayload(
            sessionStartedAt: store.session.startedAt,
            todayCount: store.todayCount
        )
        WatchLink.shared.send(payload)
    }
}

#Preview {
    WatchHomeView()
        .environment(CheckpointStore(persistence: InMemoryCheckpointStore()))
}
