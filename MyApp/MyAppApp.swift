import AppIntents
import SwiftUI
// @template:swiftdata BEGIN
import SwiftData
// @template:swiftdata END

@main
@MainActor
struct MyAppApp: App {
    @State private var store: CheckpointStore

    // @template:nse BEGIN
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // @template:nse END

    init() {
        Theme.registerFonts()

        let checkpointStore = CheckpointStore(persistence: Self.makePersistence())
        _store = State(initialValue: checkpointStore)

        // App Intents resolve `@Dependency var store` against this registration,
        // which is the reason CheckpointStore needs no singleton.
        AppDependencyManager.shared.add(dependency: checkpointStore)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onAppear {
                    // One observation hook fans out to every enabled mirror;
                    // each mirror strips independently with its component.
                    store.onSnapshot = { snapshot in
                        // @template:live-activity BEGIN
                        LiveActivityController.shared.sync(
                            session: SessionState(startedAt: snapshot.sessionStartedAt),
                            todayCount: snapshot.todayCount
                        )
                        // @template:live-activity END
                        // @template:watch BEGIN
                        WatchLink.shared.pushContext(WatchPayload(snapshot))
                        // @template:watch END
                    }
                    // @template:live-activity BEGIN
                    LiveActivityController.shared.sync(
                        session: store.session,
                        todayCount: store.todayCount
                    )
                    // @template:live-activity END
                    // @template:watch BEGIN
                    // Touching .shared activates the WCSession; the initial
                    // push mirrors current state before the first mutation.
                    WatchLink.shared.pushContext(WatchPayload(
                        sessionStartedAt: store.session.startedAt,
                        todayCount: store.todayCount
                    ))
                    // @template:watch END
                }
                // @template:nse BEGIN
                .onAppear { appDelegate.registerForRemoteNotifications() }
                // @template:nse END
        }
    }

    /// The persistence seam. `swiftdata` supplies the durable implementation;
    /// without it the in-memory store is the entire contract.
    private static func makePersistence() -> any CheckpointPersisting {
        // @template:swiftdata BEGIN
        // The container belongs to the persistence layer alone. This Scene
        // deliberately carries no `.modelContainer(_:)`: opening the App Group
        // store twice in one process yields two contexts and stale reads, and
        // no view in this template uses @Query.
        if let container = try? SwiftDataCheckpointStore.makeContainer() {
            return SwiftDataCheckpointStore(container: container)
        }
        // @template:swiftdata END
        return InMemoryCheckpointStore()
    }
}
