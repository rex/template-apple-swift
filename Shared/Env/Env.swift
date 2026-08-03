// Env — runtime configuration, resolved in one documented order.
//
//   1. UserDefaults override  (a debug/settings screen wrote it)
//   2. ProcessInfo            (a scheme's environment variables, or CI)
//   3. Environment.plist      (bundled per target; gitignored)
//   4. compiled-in default
//
// Environment.plist ships inside the app bundle and is readable by anyone with
// the .ipa. It is for endpoints and feature flags, never for credentials —
// those live in the Keychain at runtime.

import Foundation

public nonisolated enum Env {
    /// Bundled resource name. `Environment.example.plist` is the tracked
    /// template; `Environment.plist` itself is gitignored.
    public static let resourceName = "Environment"

    // MARK: - Typed accessors
    //
    // A template earns exactly two: one flag and one endpoint. Add app keys
    // here rather than scattering `Env.value(forKey:)` calls through views.

    /// Surfaces sample content so the app is demoable without a backend.
    public static var demoMode: Bool {
        bool(forKey: "DEMO_MODE", default: false)
    }

    /// `nil` (absent or empty) means "no backend" — the app runs local-only.
    public static var apiBaseURL: URL? {
        url(forKey: "API_BASE_URL")
    }

    // MARK: - Generic resolution

    public static func value(forKey key: String) -> String? {
        if let override = nonEmpty(UserDefaults.standard.string(forKey: storageKey(for: key))) {
            return override
        }
        if let process = nonEmpty(ProcessInfo.processInfo.environment[key]) {
            return process
        }
        // Plist scalars (Bool, Int, Double) bridge to NSNumber; normalising to
        // String here keeps every accessor below on one code path.
        guard let raw = plist[key] else { return nil }
        switch raw {
        case let string as String: return nonEmpty(string)
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    public static func bool(forKey key: String, default fallback: Bool) -> Bool {
        guard let raw = value(forKey: key), let parsed = Bool(loose: raw) else { return fallback }
        return parsed
    }

    public static func integer(forKey key: String, default fallback: Int) -> Int {
        guard let raw = value(forKey: key), let parsed = Int(raw) else { return fallback }
        return parsed
    }

    public static func url(forKey key: String) -> URL? {
        guard let raw = value(forKey: key) else { return nil }
        return URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
    }

    // MARK: - Overrides (symmetric getter / setter / reset)

    public static func override(forKey key: String) -> String? {
        nonEmpty(UserDefaults.standard.string(forKey: storageKey(for: key)))
    }

    /// Pass `nil` or an empty string to clear a single override.
    public static func setOverride(_ value: String?, forKey key: String) {
        let defaults = UserDefaults.standard
        var index = Set(defaults.stringArray(forKey: overrideIndexKey) ?? [])

        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(value, forKey: storageKey(for: key))
            index.insert(key)
        } else {
            defaults.removeObject(forKey: storageKey(for: key))
            index.remove(key)
        }
        defaults.set(index.sorted(), forKey: overrideIndexKey)
    }

    public static func clearOverrides() {
        let defaults = UserDefaults.standard
        for key in defaults.stringArray(forKey: overrideIndexKey) ?? [] {
            defaults.removeObject(forKey: storageKey(for: key))
        }
        defaults.removeObject(forKey: overrideIndexKey)
    }

    // MARK: - Plumbing

    private static let overridePrefix = "env.override."
    private static let overrideIndexKey = "env.override.keys"

    private static func storageKey(for key: String) -> String { overridePrefix + key }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    /// `[String: Any]` cannot express Sendability. The box is honest: it is
    /// written exactly once during static initialization and never mutated.
    private nonisolated struct PlistValues: @unchecked Sendable {
        let raw: [String: Any]
        subscript(key: String) -> Any? { raw[key] }
    }

    private static let plist = PlistValues(raw: loadPlist())

    private static func loadPlist() -> [String: Any] {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }
}

private nonisolated extension Bool {
    /// Liberal coercion so a plist `<true/>`, an `Xcode scheme "1"`, and a CI
    /// `"YES"` all mean the same thing.
    init?(loose raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on": self = true
        case "0", "false", "no", "n", "off": self = false
        default: return nil
        }
    }
}
