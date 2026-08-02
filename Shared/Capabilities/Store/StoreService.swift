// StoreKit 2 entitlement service. Component: `store`.
//
// API-driven on purpose (Product.products / purchase / Transaction.updates /
// Transaction.currentEntitlements) rather than SubscriptionStoreView: the
// SwiftUI merchandising views need a real App Store Connect subscription group
// and render a failure state against the template's placeholder identifiers,
// which leaves an agent nothing compilable to extend. See PaywallView.swift for
// the production upgrade path.

import Foundation
import StoreKit

@MainActor
@Observable
public final class StoreService {
    public private(set) var products: [Product] = []
    public private(set) var purchasedProductIDs: Set<String> = []

    public var isPro: Bool { !purchasedProductIDs.isEmpty }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    public init() {}

    /// Call once at launch. The `Transaction.updates` listener must outlive any
    /// view — a purchase can complete after a paywall is dismissed (Ask to Buy,
    /// SCA challenges, interrupted purchases), and an unconsumed update is
    /// redelivered forever.
    public func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.apply(result)
            }
        }
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    public func refresh() async {
        products = (try? await Product.products(for: ProductIDs.all)) ?? []
        await refreshEntitlements()
    }

    public func purchase(_ product: Product) async throws {
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            // Product.PurchaseResult is non-frozen; stay source-compatible.
            break
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            owned.insert(transaction.productID)
        }
        purchasedProductIDs = owned
    }

    private func apply(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? Self.checkVerified(result) else { return }
        purchasedProductIDs.insert(transaction.productID)
        await transaction.finish()
    }

    /// `VerificationResult` is `@frozen`, so no `@unknown default` here.
    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }
}
