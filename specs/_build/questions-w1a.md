# Questions / decisions — W1A (project structure)

Raised against FROZEN contracts v1. Everything below was coded to the
contract as written; these are the places where the contract is ambiguous,
self-contradictory, or where W1A exercised the authority §6 grants it
("W1A finalizes the per-target mode").

## Q1 — §6 says "six target-bearing components", then lists seven

> "Component `.yml` files exist only for the six target-bearing components
> (`mac`, `watch`, `complications`, `widgets-home`, `widget-mac`,
> `live-activity`, `nse`)."

That enumeration has seven IDs, and §3 marks seven components as bringing a
target. Shipped **seven** files. Read "six" as a typo; no other reading is
consistent with §2's target registry.

## Q2 — plist/entitlement mode finalized: everything generated

§6 says prefer xcodegen-generated `info:`/`entitlements:`; §6 also gives W1A
the call. Decision:

- **All 8 app/extension targets**: Info.plist AND .entitlements generated from
  YAML (`info: {path, properties}` / `entitlements: {path, properties}`), at
  the conventional `<TargetDir>/Info.plist` and
  `<TargetDir>/<Target>.entitlements` paths.
- **Both test bundles**: `GENERATE_INFOPLIST_FILE: 'YES'`. Nothing in a test
  plist is component-mergeable, and generating one would write a file into
  W1B's test tree for no benefit.
- **`PrivacyInfo.xcprivacy`**: hand-authored, one per target (8 files). It is
  a bundled resource, not a managed plist — generation cannot express it.
  This is the only hand-authored plist, justified in a comment in the file.

Consequences other waves must absorb:

1. `.gitignore` now ignores `**/Info.plist` and `**/*.entitlements` globally
   (they are regenerated on every `xcodegen generate`; a committed copy would
   invite an Xcode Signing-&-Capabilities edit that the next generate
   silently reverts).
2. **`template/components.yaml`'s `entitlements:` and `infoplist:` maps are
   now wrong for `nse` and `live-activity`.** Their keys ride
   `xcodegen/components/{nse,live-activity}.yml` and disappear when the file
   is deleted — no plistlib editing, no key lists. W2A should drop those two
   maps (schema_version 0 → 1 is where this belongs).
3. `verify.py` should assert the generated mode: every target has an explicit
   `PRODUCT_BUNDLE_IDENTIFIER` in YAML, every extension ID is its host's plus
   exactly one dot-segment, and no on-disk `Info.plist` / `*.entitlements` is
   tracked by git.
4. The App Group is declared explicitly on all 8 app/extension targets rather
   than once in a template — arrays concatenate without dedup (a target that
   also declared it would ship the group twice), and a `properties:` map that
   pruning empties parses as null and fails generation. `verify.py` can
   therefore assert `grep -c group.com.example.myapp` over the YAML surface
   == 8, matching contracts §1's own accounting. Both plist templates supply
   only `path:`, so a target that forgets `properties:` fails loudly.

## Q3 — `account` / `health` keys: YAML marker blocks (§5 vs §6 tension)

§6: "*Exception to the one-owner rule: `account`'s SIWA/iCloud entitlement
keys ride marker-gated `entitlements.properties` handled by W1A.*"
§5: marker blocks appear ONLY in the enumerated Swift files, grammar
`// @template:<id> BEGIN/END`.

These two cannot both hold literally. `account` and `health` own no component
`.yml` (§6/D8), their keys must live in YAML because the host plists are now
generated (Q2), and plistlib-editing a generated file would be reverted by the
next `xcodegen generate`. So the keys are gated by **YAML** marker blocks:

```yaml
        # @template:account BEGIN
        com.apple.developer.applesignin:
          - Default
        # @template:account END
```

Grammar: whole-line, `#`-prefixed (YAML has no `//` comments), otherwise
identical to §5. Occurrences — exactly three blocks, all authored by W1A:

| File | Block | Keys |
|---|---|---|
| `project.yml` | `account` | `targets.MyApp.entitlements.properties`: applesignin, icloud-services, icloud-container-identifiers |
| `project.yml` | `health` | `targets.MyApp.entitlements.properties`: healthkit — and `targets.MyApp.info.properties`: NSHealthShare/UpdateUsageDescription (two separate blocks, same id) |
| `xcodegen/components/mac.yml` | `account` | `targets.MyAppMac.entitlements.properties`: same three keys |

Asks:
- **W2A**: `prune.py` must strip `#`-form blocks in `.yml` as well as `//`-form
  blocks in `.swift`; `verify.py`'s orphan-marker check must cover both.
  `components.yaml` for `account`/`health` should replace its `entitlements:` /
  `infoplist:` plistlib maps with the marker-file list above.
- **Fable**: if this deviation from §5 is unacceptable, the only other design
  that survives Q2 is giving `account` and `health` their own
  `xcodegen/components/*.yml` — which contradicts §6/D8 instead. Pick one.

## Q4 — watch companion key spelled as a build setting in §2

§2 requires `INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.example.myapp`.
`INFOPLIST_KEY_*` settings are only merged when `GENERATE_INFOPLIST_FILE=YES`;
under Q2's generated-plist mode they are inert. Shipped as the equivalent
plist property `WKCompanionAppBundleIdentifier`, plus `WKApplication: true`
(without which a single-target watchOS app is read as the legacy WatchKit
app/extension pair and never installs). Same requirement, effective spelling.

## Q5 — AppIcon ships with no image files

`MyApp/Assets.xcassets/AppIcon.appiconset/Contents.json` declares the
ios/watchos/mac wells but names **no** filenames. Referencing a PNG that is
not in the repo is an `actool` error, and no binary assets are checked in.
Consequence: builds are green, archive/upload is not until the owner drops a
1024×1024 icon in. W2D should say so in the onboarding docs; W2B's `release`
lane will otherwise fail late with ITMS-90236.

## Q6 — scheme names are now API for W2B and W2C

Four schemes exist: `MyApp` (unit tests, `gatherCoverageData: true`),
`MyAppScreenshots` (builds MyApp, runs `MyAppUITests` — the fastlane
`snapshot` driver per ADR-0009 C10), `MyAppMac` (from `mac.yml`), `MyAppWatch`
(from `watch.yml`). UI tests are deliberately NOT in the `MyApp` scheme so
`make test` stays fast — `make ui-test` must name `MyAppScreenshots`.

## Q7 — cross-partition paths this spec hard-codes

If W1B/W1C name anything differently, the project will not generate. Assumed:
`Shared/Sync/WidgetSync.swift`, `Shared/Sync/WatchSync.swift` (excluded from
the macOS target — WatchConnectivity has no macOS implementation),
`Shared/SessionActivityAttributes.swift`, `Shared/Theme/`,
`Shared/Capabilities/{Store,Account,Health}/`, `Shared/Resources/`,
`Tests/MyAppTests/`, `UITests/`, and one directory per target named exactly
as the target. The NSE's principal class must be `NotificationService` in
module `NotificationService` (`$(PRODUCT_MODULE_NAME).NotificationService`).

## Q8 — two soft spots left deliberately inert

- `options.preGenCommand` calls `scripts/apple/generate-build-info.sh` (W2C)
  and `MyApp/Generated/BuildInfo.swift` is an `optional: true` source. Both
  are no-ops if W2C ships neither; the preGenCommand is guarded because a
  non-zero exit aborts generation.
- The iOS host declares `UIBackgroundModes: [fetch, processing]` and
  `BGTaskSchedulerPermittedIdentifiers: [com.example.myapp.refresh]`. If W1C
  ships no BGTask scheduling these are dead keys App Review can question; the
  plist carries a comment saying to drop unused modes before submitting.
