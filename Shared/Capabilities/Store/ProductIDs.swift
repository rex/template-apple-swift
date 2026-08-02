// Product identifiers. Component: `store`.
//
// Replace these at onboarding with the identifiers you created in App Store
// Connect. Unknown identifiers are not an error: `Product.products(for:)`
// returns an empty array, so the paywall renders its empty state and the app
// still builds and runs with no ASC configuration at all.

import Foundation

public nonisolated enum ProductIDs {
    /// One non-consumable / subscription is enough to demonstrate the seam.
    public static let pro = "com.example.myapp.pro.yearly"

    public static let all: [String] = [pro]
}
