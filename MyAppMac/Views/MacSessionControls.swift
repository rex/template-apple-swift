import SwiftUI

@MainActor
struct MacSessionControls: View {
    @Environment(CheckpointStore.self) private var store
    @State private var note = ""

    private static let maxSessionSeconds: TimeInterval = 24 * 60 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            elapsed
            sessionButton

            Divider()

            TextField("Note (optional)", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(Theme.font.body)
                .lineLimit(1...3)

            Button("Log checkpoint") {
                store.logCheckpoint(note: note.isEmpty ? nil : note)
                note = ""
            }
            .disabled(!store.session.isActive)
            .keyboardShortcut("l", modifiers: [.command])

            Spacer()
        }
        .padding(Theme.spacing.medium)
    }

    private var elapsed: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
            Text("Elapsed")
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)

            if let startedAt = store.session.startedAt {
                Text(
                    timerInterval: startedAt...startedAt.addingTimeInterval(Self.maxSessionSeconds),
                    countsDown: false
                )
                .font(Theme.font.title)
                .monospacedDigit()
            } else {
                Text("—")
                    .font(Theme.font.title)
                    .foregroundStyle(Theme.color.muted)
            }

            Text("\(store.todayCount) today")
                .font(Theme.font.caption)
                .foregroundStyle(Theme.color.muted)
        }
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
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [.command])
    }
}
