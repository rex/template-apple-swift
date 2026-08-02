import SwiftUI

@MainActor
struct MacCheckpointList: View {
    @Environment(CheckpointStore.self) private var store

    var body: some View {
        Table(sortedCheckpoints) {
            TableColumn("Time") { checkpoint in
                Text(checkpoint.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.font.body)
                    .monospacedDigit()
            }
            TableColumn("Note") { checkpoint in
                Text(checkpoint.note ?? "—")
                    .font(Theme.font.body)
                    .foregroundStyle(checkpoint.note == nil ? Theme.color.muted : Theme.color.foreground)
            }
        }
        .overlay {
            if store.checkpoints.isEmpty {
                ContentUnavailableView(
                    "No checkpoints",
                    systemImage: "flag.checkered",
                    description: Text("Start a session and log one to see it here.")
                )
            }
        }
    }

    private var sortedCheckpoints: [Checkpoint] {
        store.checkpoints.sorted { $0.timestamp > $1.timestamp }
    }
}
