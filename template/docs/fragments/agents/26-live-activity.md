`LiveActivity/` — Live Activity + Dynamic Island. `SessionActivityAttributes`
is guarded `#if os(iOS)`, never `canImport(ActivityKit)` (it imports on macOS).
