// HealthKit probe. Component: `health` (default OFF).
//
// `#if os(iOS)` and NOT `#if canImport(HealthKit)`: HKHealthStore is declared
// on macOS 13+ and visionOS too, so `canImport` is true there and the guard
// would do nothing.
//
// Per `.claude/rules/security.md`: sample values are never logged, never
// written to the App Group, and never leave the device.

#if os(iOS)
import Foundation
import HealthKit

@MainActor
@Observable
public final class HealthService {
    public private(set) var todayStepCount: Double?
    public private(set) var didRequestAuthorization = false

    @ObservationIgnored private let store = HKHealthStore()

    public init() {}

    /// False on iPad and in any environment without a Health database. Check it
    /// before showing the capability in Settings at all.
    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// One read scope is all the template asks for. Requesting more than the
    /// app demonstrably uses is an App Review finding.
    public func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [Self.stepType])
        didRequestAuthorization = true
    }

    /// Modern async query descriptor — `HKSampleQuery` with a completion
    /// handler is the legacy shape and does not belong in new code.
    ///
    /// For "today's total" a real app should use `HKStatisticsQueryDescriptor`,
    /// which sums in the Health store instead of shipping every sample across
    /// the XPC boundary. This reads one sample to keep the seam minimal.
    public func refreshLatestSteps() async throws {
        guard isAvailable else { return }

        let startOfDay = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: .now)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.stepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )

        // `requestAuthorization` never reports whether READ access was granted
        // (authorizationStatus reports write permission only), so an empty
        // result is a normal outcome, not an error. Never branch UI on status.
        let samples = try await descriptor.result(for: store)
        todayStepCount = samples.first?.quantity.doubleValue(for: .count())
    }

    private static let stepType = HKQuantityType(.stepCount)
}
#endif
