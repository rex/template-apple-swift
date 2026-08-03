// CloudKit account probe. Component: `account`.
//
// The container is only queried for its account status — this template stores
// nothing in CloudKit. It exists so the entitlement pair
// (com.apple.developer.icloud-services + icloud-container-identifiers) has a
// live call site and an obvious place to grow.

import CloudKit
import Foundation

public nonisolated enum CloudKitStatus {
    public static func current() async -> CKAccountStatus {
        (try? await CKContainer.default().accountStatus()) ?? .couldNotDetermine
    }

    /// Everything other than `.available` means "no cloud". Treat it as a
    /// state, not an error — `.temporarilyUnavailable` in particular resolves
    /// on its own once the device finishes signing in.
    public static func isUsable(_ status: CKAccountStatus) -> Bool {
        status == .available
    }

    /// Log lines only. User-facing copy lives in SignInView so the String
    /// Catalog picks it up.
    public static func debugLabel(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default: return "unknown"
        }
    }
}
