import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(CheckpointStore.self) private var store
    @State private var note = ""

    /// Upper bound for the self-advancing timer range. A session that outlives
    /// a day is a bug, not a display case.
    private static let maxSessionSeconds: TimeInterval = 24 * 60 * 60

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacing.large) {
                    elapsedCard
                    sessionButton
                    logCard
                }
                .padding(Theme.spacing.medium)
            }
            .background(Theme.color.background)
            .navigationTitle("MyApp")
        }
    }

    private var elapsedCard: some View {
        VStack(spacing: Theme.spacing.small) {
            Text("Elapsed")
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)

            if let startedAt = store.session.startedAt {
                // Self-advancing: the system re-renders this without a
                // publisher, which is what lets the widget stay this cheap too.
                Text(
                    timerInterval: startedAt...startedAt.addingTimeInterval(Self.maxSessionSeconds),
                    countsDown: false
                )
                .font(Theme.font.hero)
                .monospacedDigit()
                .foregroundStyle(Theme.color.foreground)
            } else {
                Text("—")
                    .font(Theme.font.hero)
                    .foregroundStyle(Theme.color.muted)
            }

            Text("\(store.todayCount) today")
                .font(Theme.font.caption)
                .foregroundStyle(Theme.color.muted)
                .accessibilityIdentifier("todayCountLabel")
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacing.large)
        .background(Theme.color.surface, in: RoundedRectangle(cornerRadius: Theme.radius.large))
    }

    private var sessionButton: some View {
        Button {
            if store.session.isActive {
                store.endSession()
            } else {
                store.startSession()
            }
        } label: {
            Label(
                store.session.isActive ? "Stop session" : "Start session",
                systemImage: store.session.isActive ? "stop.fill" : "play.fill"
            )
            .font(Theme.font.headline)
            .frame(maxWidth: .infinity)
            .padding(Theme.spacing.small)
        }
        .buttonStyle(.borderedProminent)
        .tint(store.session.isActive ? Theme.color.danger : Theme.color.accent)
        // The identifier is the contract with MyAppUITests and the fastlane
        // snapshot lane; button labels are localized and must never be matched.
        .accessibilityIdentifier(store.session.isActive ? "endSessionButton" : "startSessionButton")
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Checkpoint")
                .font(Theme.font.headline)
                .foregroundStyle(Theme.color.foreground)

            TextField("Note (optional)", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.font.body)
                .lineLimit(1...3)
                .padding(Theme.spacing.small)
                .background(Theme.color.background, in: RoundedRectangle(cornerRadius: Theme.radius.small))
                .accessibilityIdentifier("checkpointNoteField")

            Button("Log checkpoint") {
                store.logCheckpoint(note: note.isEmpty ? nil : note)
                note = ""
            }
            .buttonStyle(.bordered)
            .font(Theme.font.label)
            .disabled(!store.session.isActive)
            .accessibilityIdentifier("logCheckpointButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing.large)
        .background(Theme.color.surface, in: RoundedRectangle(cornerRadius: Theme.radius.large))
    }
}

#Preview {
    HomeView()
        .environment(CheckpointStore(persistence: InMemoryCheckpointStore()))
}
