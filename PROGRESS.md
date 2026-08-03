# PROGRESS

<!-- ≤50 lines. Read first on a fresh session; points at TASK_STATE.md for
     detail. TEMPLATE MODE: template/generate.py replaces this file at
     onboarding with a real session pointer. -->

- **Project**: `template-apple-swift` — the template itself, un-onboarded.
- **Stack**: swift-apple-universal (iOS + macOS + watchOS + 5 extensions).
- **State**: construction COMPLETE (v0.8.0). verify-macos run #7: all six
  combos green end-to-end — build (10 targets), Swift Testing, XCUITest
  smoke. No app has been stamped from this checkout.

## If you are here to USE the template

Run `/onboard`. Nothing else in this file applies until you have.

## If you are here to MAINTAIN the template

Read in this order:

1. `AGENTS.md` — the contract for working in this repo.
2. `docs/template-guide.md` — markers, the component registry, combos, and
   how to add a component.
3. `MAP.md` — where the machinery lives and what breaks what.
4. `TASK_STATE.md` — the active slice, if construction is still in flight.
5. `docs/adr/README.md` — why the design is the way it is.

## Standing decisions

- Superset-and-prune, not scaffold-and-fill (ADR-0001).
- XcodeGen-native composition; no YAML markers, no spec splicing (ADR-0006).
- Zero Serena; MCP credentials via `headersHelper` + 1Password (ADR-0005).
- Linux gates on every push; macOS compile matrix on dispatch (ADR-0003).
- The generator is one-shot and runs no git commands (ADR-0009).

## Do NOT

- Start feature work in an un-onboarded tree.
- "Fix" `MyApp` / `com.example.myapp` by hand — they are rename tokens.
- Hand-edit `MyApp.xcodeproj`, any `Info.plist`, or any `.entitlements`.
- Add a component's files without a `template/components.yaml` entry.
