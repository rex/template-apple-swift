import Foundation

/// Build metadata seam for the Settings screen.
///
/// `MyApp/Generated/BuildInfo.swift` is written by
/// `scripts/apple/generate-build-info.sh` and is `optional: true` in
/// project.yml, so it is absent on a fresh clone and cannot be referenced
/// directly by any file that must always compile. This protocol is the seam:
/// the bundle-backed default is always correct, and a repo that keeps the
/// generated file adds its own conformer and assigns `AppInfo.current`.
@MainActor
protocol BuildInfoProviding {
    var versionLabel: String { get }
    var buildLabel: String { get }
    /// Git provenance (short SHA, commit date). `nil` when only the bundle is known.
    var provenanceLabel: String? { get }
}

@MainActor
struct BundleBuildInfo: BuildInfoProviding {
    var versionLabel: String { Self.string(for: "CFBundleShortVersionString") }
    var buildLabel: String { Self.string(for: "CFBundleVersion") }
    var provenanceLabel: String? { nil }

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }
}

@MainActor
enum AppInfo {
    /// Swap in a richer provider from `MyAppApp.init()` when the generated
    /// `BuildInfo` enum is part of the target.
    static var current: any BuildInfoProviding = BundleBuildInfo()
}
