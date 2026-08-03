## 5. Code style

- Swift API Design Guidelines; 4-space indent; explicit access control.
- `@Observable` + `@State`/`@Environment`. `ObservableObject`, `@Published`,
  `@StateObject` and `@EnvironmentObject` are forbidden and gate-checked.
- Business logic lives in stores/services; SwiftUI views stay declarative and
  use `Theme` tokens — no magic numbers, hex literals or ad-hoc fonts.
- Files: 250 lines soft, 400 hard. Split by responsibility, not by line count.

## 6. Testing

Swift Testing (`@Test`/`#expect`); `make test` must be green before done. UI
tests live in their own scheme so `make test` stays fast.

## 7. Security (hard stops)

- No secrets in source. Runtime config loads through `Env`; only
  `Environment.example.plist` is committed.
- `DEVELOPMENT_TEAM` lives in `Config/Shared.xcconfig` and nowhere else — an
  `.xcconfig` is the lowest precedence layer, so the same key in `project.yml`
  would silently win. Same for `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
  (`Config/Versions.xcconfig`, written by CI).
- Never commit `AuthKey_*.p8`, `*.p12`, or `*.mobileprovision`.
