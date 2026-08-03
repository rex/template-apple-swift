// Sign in with Apple screen. Component: `account`.
//
// Owns its own AccountService for the same reason PaywallView does: the view
// must be constructible from any target with no environment contract.

import AuthenticationServices
import CloudKit
import SwiftUI

public struct SignInView: View {
    @State private var account = AccountService()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.large) {
            accountRow
            iCloudRow

            if case .signedIn = account.state {
                Button("Sign Out") { account.signOut() }
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.danger)
                    .accessibilityIdentifier("signOutButton")
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    account.handle(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: Theme.size.control)
                .accessibilityIdentifier("signInWithAppleButton")
            }
        }
        .padding(Theme.spacing.large)
        .background(Theme.color.background)
        .task { await account.refresh() }
    }

    private var accountRow: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xs) {
            switch account.state {
            case .unknown:
                Text("Checking your Apple Account…")
            case .signedOut:
                Text("Not signed in")
            case .signedIn:
                Text("Signed in with Apple")
            case .revoked:
                Text("Access was revoked in Settings. Sign in again to continue.")
            }
        }
        .font(Theme.font.headline)
        .foregroundStyle(Theme.color.foreground)
    }

    private var iCloudRow: some View {
        HStack(spacing: Theme.spacing.small) {
            Circle()
                .fill(CloudKitStatus.isUsable(account.iCloudStatus)
                      ? Theme.color.success
                      : Theme.color.muted)
                .frame(width: Theme.spacing.small, height: Theme.spacing.small)

            switch account.iCloudStatus {
            case .available:
                Text("iCloud is available")
            case .noAccount:
                Text("No iCloud account is signed in on this device")
            case .restricted:
                Text("iCloud is restricted by parental controls or a profile")
            case .temporarilyUnavailable:
                Text("iCloud is temporarily unavailable")
            default:
                Text("iCloud status is unknown")
            }
        }
        .font(Theme.font.caption)
        .foregroundStyle(Theme.color.muted)
    }
}

#Preview {
    SignInView()
}
