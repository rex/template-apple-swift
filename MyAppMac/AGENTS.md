# AGENTS.md (for /MyAppMac)

Rules for the `MyAppMac` macOS application target. Inherits everything in the
root `AGENTS.md`; the nearest file wins on conflict.

## 1. Module overview

SwiftUI Mac app: a main window (`MacRootView`) with session controls and a
checkpoint table, plus a `Settings` scene. Shares `com.example.myapp` with the
iOS app so App Store Connect resolves one app record — Universal Purchase
breaks the moment those two bundle IDs diverge.

## 2. Commands

```bash
xcodebuild -project MyApp.xcodeproj -scheme MyAppMac \
  -destination 'platform=macOS' build
```

## 3. Conventions

- Theme tokens only, `@Observable` only, explicit isolation on every type.
- `MacRootView.swift` carries the `store` and `account` marker blocks. Keep the
  Mac settings sections a mirror of `MyApp/Views/SettingsView.swift`; there is
  no `health` section on macOS.

## 4. Hazards

- **No menu-bar surface ships in v1 (ADR-0009.)** The macOS 26 menu-bar layer
  regressed for both `MenuBarExtra` and hand-rolled `NSStatusItem` (status items
  that never register, `isVisible` lying about hidden items). `NSStatusItem` is
  not a reliable escape hatch. Re-test on the current macOS before adding one,
  and read `docs/template-guide.md` first.
- macOS has no WatchConnectivity: anything reaching for `WCSession` must be
  excluded from this target's sources or guarded.
- App Sandbox + hardened runtime are both on. Adding a capability means adding
  an entitlement — and every entitlement change is documented, per root rules.
- The App Group string is the unprefixed `group.com.example.myapp` on every
  platform. macOS also accepts `<TeamID>.group.…`; mixing spellings is what
  silently breaks cross-process reads.
