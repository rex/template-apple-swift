# W1B questions / notes (Shared tree + tests)

Written per the "code to the contract as written, record the delta" rule. No
file outside the W1B partition was changed on account of anything below.

## A. `template/components.yaml` changes W2A must make

1. **`live-activity.owns.files` must gain
   `Tests/MyAppTests/ActivityAttributesTests.swift`.** Contracts §5 already says
   component test files are whole-file owned; the registry does not list any yet.
2. **`swiftdata.owns.files` must gain `Tests/MyAppTests/SwiftDataStoreTests.swift`.**
   Same reason. Its two source entries (`Shared/Store/SwiftDataCheckpointStore.swift`,
   `Shared/Models/CheckpointModel.swift`) are correct as written.
3. **`watch`: `Shared/Sync/WatchSync.swift` should move from `marker_files` to
   `owns.files`, and `Shared/Sync/WatchLink.swift` added alongside it.** The
   registry's own comment says "prefer whole-file"; both files are whole-file,
   contain no markers, and are wrapped in
   `#if (os(iOS) || os(watchOS)) && canImport(WatchConnectivity)`.
4. **`Shared/Store/CheckpointStore.swift` contains TWO `live-activity` blocks**
   (the `onSnapshot` property declaration and its call site in `publish()`) and
   ONE `swiftdata` block. `prune.py` must strip every block for a disabled
   component in a file, not just the first.

## B. contracts.md internal inconsistency (coded to the prose)

5. **§4.1 code block vs. prose.** The block shows `public enum WidgetSyncKey`
   and `public struct WidgetSnapshot` with no isolation, while the prose two
   paragraphs later says "All four types in this file … are explicitly
   `nonisolated`", and the §4 preamble requires explicit isolation on every
   type. I wrote all four as `nonisolated`. Member signatures are unchanged, so
   nothing that reads §4.1 for API shape is affected. Suggest the code block be
   updated to match at the next contracts revision.

## C. Cross-partition contracts other Wave-1/2 agents need

6. **UI test ↔ app accessibility identifier.** `UITests/MyAppUITests/LaunchTests.swift`
   hard-asserts `app.buttons["startSessionButton"]` (R4 §11's name). W1C's home
   screen must set `.accessibilityIdentifier("startSessionButton")` on the start
   button or the UI test fails at Phase 5.
7. **Public type names W1C's `SettingsView` / `MacRootView` marker blocks will
   reference** (contracts names the directories, not the types):
   - `store`: `StoreService`, `PaywallView` (has `init()`, owns its own
     service — `PaywallView()` is safe from anywhere), `ProductIDs`.
   - `account`: `AccountService`, `SignInView` (same self-owning shape),
     `CloudKitStatus`.
   - `health`: `HealthService` (whole file is `#if os(iOS)`).
8. **Store seams W1C's `@main` files should use:**
   `CheckpointStore.makeDefaultPersistence()` (carries the `swiftdata` marker
   block so hosts need none) and `CheckpointStore.onSnapshot` (the
   `live-activity` hook — assign with a `[weak controller]` capture).
9. **`MyAppTests` must run with parallel testing disabled**
   (`-parallel-testing-enabled NO`, or `parallelizable: false` in a test plan).
   `CheckpointStore` republishes the App Group snapshot on every mutation and
   `WidgetSyncTests` reads that same single slot; suite-level `.serialized` does
   not serialize across suites. Owner: W2C (Makefile / ci.yml / verify-macos).
10. **`.gitignore` must ignore `Shared/Env/Environment.plist`** (the tracked
    template is `Shared/Env/Environment.example.plist`). Owner: W1A.
11. **`CheckpointStore.shared` does not exist and should not.** R4's App Intents
    crib (§Group 4) calls `CheckpointStore.shared` but immediately flags it as
    "the pragmatic path", and R4's own Capability audit A3 rules the other way:
    register the store with `AppDependencyManager.shared.add(dependency:)` in
    `MyAppApp.init()` and read it with `@Dependency var store: CheckpointStore`.
    contracts §4.3 declares no singleton and `init(persistence:)` is the DI
    seam, so W1C's intents must use `@Dependency`.

## D. Files I created that the ownership table does not obviously assign to W1B

Both were named explicitly in the W1B brief; flagging so Wave 2 does not
clobber them.

12. `Shared/Env/Environment.example.plist` — not a `.swift` file, but also not
    one of W1A's enumerated plist classes (Info.plist / entitlements /
    PrivacyInfo.xcprivacy).
13. `Shared/AGENTS.md` and `Shared/README.md` — `file-ownership.md` §Wave 2
    gives W2D "per-target `AGENTS.md` + `README.md`". These two are written and
    current; W2D should treat them as existing content to link, not to author.

## E. Blind-write risks for the Phase-5 Mac loop to check first

14. `@Model nonisolated final class CheckpointRecord` — `nonisolated` is required
    because `PersistentModel` refines `Hashable`/`Equatable` (nonisolated
    synchronous requirements) and MainActor-default isolation would otherwise
    make the class a main-actor witness. The `@Model` macro's interaction with
    the modifier is the single least-verified line in the W1B tree.
15. `#Index<CheckpointRecord>([\.timestamp])` needs exactly the contracts §9
    floors (iOS 18 / macOS 15 / watchOS 11). Lowering any floor means deleting
    the macro, not conditionalising it.
16. `SwiftDataCheckpointStore.makeContainer(inMemory:)` passes
    `ModelConfiguration.GroupContainer.none` when in-memory, so the swiftdata
    tests do not need the App Group entitlement in the test host.
17. Type name `CheckpointRecord` lives in `Shared/Models/CheckpointModel.swift`:
    the type name is R4's, the file name is components.yaml's.
