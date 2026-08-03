// Sign in with Apple + iCloud account state. Component: `account`.
//
// Sign in with Apple is mandatory the moment the app offers any third-party
// sign-in (Google, Facebook, …) — App Review rejects without it. Shipping it
// first is cheaper than retrofitting it.

import AuthenticationServices
import CloudKit
import Foundation
import Security

@MainActor
@Observable
public final class AccountService {
    /// `nonisolated` because `Equatable`'s `==` is a nonisolated synchronous
    /// requirement; a main-actor-isolated nested enum cannot witness it.
    public nonisolated enum State: Equatable, Sendable {
        case unknown
        case signedOut
        case signedIn(userID: String)
        case revoked
    }

    public private(set) var state: State = .unknown
    public private(set) var iCloudStatus: CKAccountStatus = .couldNotDetermine

    private static let userIDKey = "account.appleUserID"

    public init() {}

    /// Call on appear and on foreground. Apple also posts
    /// `ASAuthorizationAppleIDProvider.credentialRevokedNotification`, which is
    /// the supported way to notice a revocation without polling.
    public func refresh() async {
        iCloudStatus = await CloudKitStatus.current()

        guard let userID = AccountKeychain.read(Self.userIDKey) else {
            state = .signedOut
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        switch try? await provider.credentialState(forUserID: userID) {
        case .authorized:
            state = .signedIn(userID: userID)
        case .revoked, .notFound:
            AccountKeychain.delete(Self.userIDKey)
            state = .revoked
        default:
            state = .unknown
        }
    }

    public func handle(_ result: Result<ASAuthorization, any Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        else {
            state = .signedOut
            return
        }

        // `user` is the ONLY stable identifier, and it is a cross-launch
        // identifier — Keychain, never UserDefaults. `email` and `fullName`
        // arrive on the FIRST authorization only; persist them here or they are
        // gone forever.
        AccountKeychain.write(Self.userIDKey, value: credential.user)
        state = .signedIn(userID: credential.user)
    }

    /// Local sign-out. Apple has no server-side revoke API for the app to call;
    /// forgetting the identifier is the whole operation.
    public func signOut() {
        AccountKeychain.delete(Self.userIDKey)
        state = .signedOut
    }
}

/// Minimal `kSecClassGenericPassword` wrapper — one account per key.
/// Deliberately small: a real app should reach for a maintained Keychain
/// library rather than growing this.
internal nonisolated enum AccountKeychain {
    private static let service = "com.example.myapp.account"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func write(_ key: String, value: String) {
        let query = baseQuery(key)
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
