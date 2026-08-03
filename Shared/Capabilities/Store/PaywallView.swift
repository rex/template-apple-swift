// Paywall stub. Component: `store`.
//
// Owns its own StoreService so `PaywallView()` works from any target with no
// environment contract and no crash when nothing was injected. Hoist the
// service into the app and pass it in once entitlements are read outside this
// screen.

import StoreKit
import SwiftUI

public struct PaywallView: View {
    @State private var store = StoreService()
    @State private var isWorking = false
    @State private var failureMessage: String?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.large) {
            header

            if store.products.isEmpty {
                emptyState
            } else {
                ForEach(store.products, id: \.id) { product in
                    purchaseRow(for: product)
                }
            }

            Button("Restore Purchases") { restore() }
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
                .accessibilityIdentifier("paywallRestoreButton")

            if let failureMessage {
                Text(verbatim: failureMessage)
                    .font(Theme.font.caption)
                    .foregroundStyle(Theme.color.danger)
            }
        }
        .padding(Theme.spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.color.background)
        .disabled(isWorking)
        .task { store.start() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xs) {
            if store.isPro {
                Text("Pro is active")
                    .font(Theme.font.title)
                    .foregroundStyle(Theme.color.success)
            } else {
                Text("Upgrade to Pro")
                    .font(Theme.font.title)
                    .foregroundStyle(Theme.color.foreground)
            }

            Text("Unlock every surface: widgets, complications, and the Live Activity.")
                .font(Theme.font.body)
                .foregroundStyle(Theme.color.muted)
        }
    }

    /// Reached whenever the identifiers in `ProductIDs` are not configured in
    /// App Store Connect — which is the template's out-of-the-box state.
    private var emptyState: some View {
        Text("No products available. Create these identifiers in App Store Connect, or attach a StoreKit configuration file to the scheme.")
            .font(Theme.font.caption)
            .foregroundStyle(Theme.color.muted)
            .accessibilityIdentifier("paywallEmptyState")
    }

    private func purchaseRow(for product: Product) -> some View {
        Button {
            purchase(product)
        } label: {
            HStack {
                Text(verbatim: product.displayName)
                Spacer()
                Text(verbatim: product.displayPrice)
            }
            .font(Theme.font.headline)
            .padding(Theme.spacing.medium)
            .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.color.foreground)
        .accessibilityIdentifier("paywallPurchaseButton")
    }

    private func purchase(_ product: Product) {
        isWorking = true
        Task {
            defer { isWorking = false }
            failureMessage = nil
            do {
                try await store.purchase(product)
            } catch {
                failureMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        isWorking = true
        Task {
            defer { isWorking = false }
            failureMessage = nil
            do {
                try await store.restore()
            } catch {
                failureMessage = error.localizedDescription
            }
        }
    }
}

// Production upgrade path, once a real subscription group exists in App Store
// Connect — it handles pricing, localisation, offers and management for you:
//
//   SubscriptionStoreView(groupID: "<your ASC subscription group ID>")
//       .storeButton(.visible, for: .restorePurchases)
//
// It renders a failure state against placeholder identifiers, which is why the
// template ships the API-driven view above instead.

#Preview {
    PaywallView()
}
