// WatchLink — the WCSession client, and the template's hardest concurrency
// seam.
//
// Component: `watch` (whole file).
//
// `WCSession` is NOT `Sendable`, `WCSessionDelegate` is NOT `@MainActor`, and
// `[String: Any]` is `[String: any Any]`. The idiomatic-looking
// `Task { @MainActor in … session.isReachable … }` inside a delegate callback
// is a hard Swift 6 error: it captures a non-Sendable class across an isolation
// boundary. Every callback below therefore snapshots what it needs into
// Sendable locals FIRST and hops afterwards.

import Foundation

#if (os(iOS) || os(watchOS)) && canImport(WatchConnectivity)
import WatchConnectivity

@MainActor
@Observable
public final class WatchLink {
    public static let shared = WatchLink()

    public private(set) var isActivated = false
    public private(set) var isReachable = false
    public private(set) var lastPayload: WatchPayload?

    @ObservationIgnored private var delegate: WatchLinkDelegate?

    private init() {
        guard WCSession.isSupported() else { return }

        let delegate = WatchLinkDelegate(
            onState: { [weak self] activated, reachable in
                Task { @MainActor in
                    self?.isActivated = activated
                    self?.isReachable = reachable
                }
            },
            onPayload: { [weak self] payload in
                Task { @MainActor in self?.lastPayload = payload }
            }
        )
        self.delegate = delegate

        let session = WCSession.default
        // The delegate must be set before activate() or early callbacks are lost.
        session.delegate = delegate
        session.activate()
    }

    /// Latest-state-wins mirror: one slot, coalesced by the system, survives
    /// unreachability. This is the default channel for "here is the current
    /// state" and the only one this template needs.
    public func pushContext(_ payload: WatchPayload) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated
        else { return }

        let dictionary = WatchSync.encode(payload)
        guard WatchSync.isWithinPayloadLimit(dictionary) else { return }
        try? WCSession.default.updateApplicationContext(dictionary)
    }

    /// Immediate delivery when the counterpart is foregrounded, with the
    /// guaranteed-eventually queue as the fallback. Use for commands that must
    /// not be coalesced away.
    public func send(_ payload: WatchPayload) {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        let dictionary = WatchSync.encode(payload)
        guard WatchSync.isWithinPayloadLimit(dictionary) else { return }

        if session.isReachable {
            session.sendMessage(dictionary, replyHandler: nil) { _ in
                session.transferUserInfo(dictionary)
            }
        } else {
            session.transferUserInfo(dictionary)
        }
    }
}

/// Isolation-free delegate shim. Every `WCSessionDelegate` requirement is
/// nonisolated and synchronous, so the whole type is `nonisolated`; the
/// closures are immutable `let`s assigned at init, which is what makes the
/// `@unchecked Sendable` claim true rather than merely convenient.
private nonisolated final class WatchLinkDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let onState: @Sendable (Bool, Bool) -> Void
    private let onPayload: @Sendable (WatchPayload) -> Void

    init(
        onState: @escaping @Sendable (Bool, Bool) -> Void,
        onPayload: @escaping @Sendable (WatchPayload) -> Void
    ) {
        self.onState = onState
        self.onPayload = onPayload
        super.init()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        // Extract Sendable scalars HERE. Never capture `session` in a closure.
        let activated = activationState == .activated
        let reachable = session.isReachable
        onState(activated, reachable)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let activated = session.activationState == .activated
        let reachable = session.isReachable
        onState(activated, reachable)
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        onPayload(WatchSync.decode(context))
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onPayload(WatchSync.decode(message))
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        onPayload(WatchSync.decode(userInfo))
    }

    // These three requirements exist on iOS only (watch switching); declaring
    // them unguarded fails the watchOS build.
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        let activated = session.activationState == .activated
        let reachable = session.isReachable
        onState(activated, reachable)
    }
    #endif
}

#endif
