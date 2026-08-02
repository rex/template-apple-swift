import SwiftUI

@MainActor
struct HistoryView: View {
    @Environment(CheckpointStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                ForEach(days) { day in
                    Section(day.title) {
                        ForEach(day.checkpoints) { checkpoint in
                            row(for: checkpoint)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if store.checkpoints.isEmpty {
                    ContentUnavailableView(
                        "No checkpoints",
                        systemImage: "flag.checkered",
                        description: Text("Start a session and log one to see it here.")
                    )
                }
            }
            .navigationTitle("History")
        }
    }

    private var days: [CheckpointDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.checkpoints) { calendar.startOfDay(for: $0.timestamp) }
        return grouped
            .map { CheckpointDay(id: $0.key, checkpoints: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.id > $1.id }
    }

    private func row(for checkpoint: Checkpoint) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
            Text(checkpoint.timestamp.formatted(date: .omitted, time: .shortened))
                .font(Theme.font.body)
                .foregroundStyle(Theme.color.foreground)

            if let note = checkpoint.note, !note.isEmpty {
                Text(note)
                    .font(Theme.font.caption)
                    .foregroundStyle(Theme.color.muted)
            }
        }
        .padding(.vertical, Theme.spacing.xxs)
    }
}

/// `nonisolated` because `Identifiable`'s `id` requirement is nonisolated and
/// synchronous — under MainActor default isolation an unannotated struct cannot
/// witness it.
nonisolated struct CheckpointDay: Identifiable {
    let id: Date
    let checkpoints: [Checkpoint]

    var title: String { id.formatted(date: .abbreviated, time: .omitted) }
}

#Preview {
    HistoryView()
        .environment(CheckpointStore(persistence: InMemoryCheckpointStore()))
}
