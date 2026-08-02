# R2 — Apple toolchain currency + xcodegen capability audit

> Research deliverable per `contracts.md` §10. Date of research: **2026-08-02**.
> Companion file: `R2-skill-update-draft.md` (Part C).
> All Part-B source claims are verified against XcodeGen `master` (release
> 2.46.0) fetched 2026-08-02, not against memory.

---

## Verdicts

### Part A — toolchain currency

**V1. Current stable Xcode is 26.6 (17F113), released 2026-06-25; it ships
Swift 6.3 and the OS-26.5 SDKs. Xcode 27 is in beta (since WWDC26, 2026-06-08)
and must NOT be adopted by this template.**
Evidence: Xcode version index lists 26.4–26.6 → Swift 6.3, SDKs iOS/iPadOS/
tvOS/watchOS/macOS/visionOS 26.5, min host macOS Tahoe 26.2, newest = 26.6
(17F113), 2026-06-25 [S1]. GitHub's runner image confirms 26.6/17F113 as the
newest installed Xcode [S4]. Swift 6.3 released 2026-03-24 [S2]. Apple's
"What's new" hub currently fronts Xcode 27 beta + OS 27 [S3].
Hard constraint: **App Store submissions have required Xcode 26 + the 26-line
SDKs since 2026-04-28** [S9]. So Xcode 26.6 is simultaneously the floor and the
ceiling for anything we ship. Confidence: **high**.

**V2. `SWIFT_VERSION` must be `'6.0'`. It is a *language mode*, not a compiler
version — there is no `6.2` or `6.3` value, and Swift 6.3's additions are
attribute/upcoming-feature level, not a new mode.**
Evidence: Swift 6.3 release notes describe `@c`, `@specialize`,
`@inline(always)`, `@export(implementation)`, module-name selectors, Swift Build
preview — no new language mode [S2]. Confidence: **high** on `6.0`; **medium**
on "no Swift 7 mode exists yet" (absence of evidence; Swift 7 mode is a stated
long-term direction, not shipped).

**V2b. New Xcode 26 projects additionally default to
`SWIFT_APPROACHABLE_CONCURRENCY = YES` and
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. A template created today that
omits these is *not* what Xcode itself would produce.**
Evidence: "Two build settings are set by default for new Xcode 26 projects:
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
`SWIFT_APPROACHABLE_CONCURRENCY = YES`"; new projects get MainActor default
isolation, migrated projects get `nonisolated` [S10]. This is materially good
for us: contracts §4.3 already declares `CheckpointStore` `@MainActor`, and
`WidgetSync`/`Checkpoint` are `Sendable` — MainActor-by-default makes the
SwiftUI/widget code compile with far fewer annotations. Confidence: **high**.

**V3. CI runner: use `runs-on: macos-26` and select Xcode with a plain
`sudo xcode-select -s /Applications/Xcode_26.6.app` — no third-party action
required.**
Evidence: `macos-26` went GA 2026-02-26, is arm64-native, and became the
`macos-latest` alias in June 2026 [S5][S6]. Image `20260728.0273.1` (macOS
26.5.2) ships Xcode 26.6 (default, `/Applications/Xcode_26.6.app`), 26.5,
26.4.1, 26.3, 26.2, 26.1.1, 26.0.1 [S4]. Labels: `macos-26` (arm64 std),
`macos-26-intel` (x64), `macos-26-large` (x64), `macos-26-xlarge` (arm64) [S5].
Because the default is already 26.6, `xcode-select` is a *pin*, not a fix — but
pin it anyway so a future default rotation can't silently move us.
Corollary (ADR-0003 SHA-pin rule): using `xcode-select` instead of
`maxim-lobanov/setup-xcode@v1` removes one third-party action we'd otherwise
have to SHA-pin and Renovate. Confidence: **high**.

**V3b. Runner image tool inventory changes what `verify-macos.yml` must
install: `xcodegen` is NOT preinstalled and `swiftlint` is NOT preinstalled;
`fastlane` 2.237.0 and SwiftFormat 0.62.1 ARE preinstalled (Homebrew 6.0.13).**
Evidence: image readme tool list [S4]. Consequence: the workflow needs
`brew install xcodegen xcbeautify` (and `swiftlint` if we lint), but must NOT
`gem install fastlane` — use the preinstalled one or `bundle install` against
our pinned Gemfile (ADR-0002 commits `Gemfile.lock`, so `bundle install` is the
right call and the preinstalled fastlane is merely a warm cache).
Confidence: **high**.

**V3c. Runner-image lifecycle: `macos-14` began deprecation 2026-07-06 and is
fully unsupported 2026-11-02; `macos-15` survives, and `macos-15-intel` is the
last x86_64 Actions image (available until Aug 2027, image retired Fall 2027).**
Evidence: [S7][S6]. Consequence: no macos-14/15 anywhere in template output;
`macos-26` only. Confidence: **high**.

**V4. `iPhone 15` and `Apple Watch Series 9 (45mm)` DO NOT EXIST on the current
runner image. Any `-destination` naming them fails.** Recommended defaults:
`DEVICE ?= iPhone 17`, `WATCH_DEVICE ?= Apple Watch Series 11 (46mm)`.
Evidence — verbatim device list on image 20260728 [S4]:
- iOS 26.5 runtime: `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`,
  `iPhone 17e`, `iPhone Air`, `iPad (A16)`, `iPad Air 11-inch (M4)`,
  `iPad Air 13-inch (M4)`, `iPad mini (A17 Pro)`, `iPad Pro 11-inch (M5)`,
  `iPad Pro 13-inch (M5)`. (iOS 26.2 runtime adds `iPhone 16e` and M3 iPads.)
- watchOS 26.5 runtime: `Apple Watch SE 3 (40mm)`, `Apple Watch SE 3 (44mm)`,
  `Apple Watch Series 11 (42mm)`, `Apple Watch Series 11 (46mm)`,
  `Apple Watch Ultra 3 (49mm)`.
- Runtimes installed: iOS/tvOS/watchOS/visionOS 26.2, 26.4(.1), 26.5.
Two hardening rules follow, both cheap:
1. `make build*` should use `-destination 'generic/platform=iOS Simulator'`
   (and `generic/platform=watchOS Simulator`) — a *build* needs no concrete
   device, which removes device-name fragility from 80% of our xcodebuild calls.
   Only `make test` / `ui-test` need a named device.
2. Ship `scripts/apple/pick-simulator.sh` that resolves `DEVICE` via
   `xcrun simctl list devices available --json` and falls back to the newest
   available iPhone. Hardcoding a device name in a template that outlives one
   Xcode cycle is the exact defect we just found in Pennywise and the skill.
Confidence: **high**.

**V5. Deployment floor for a NEW template today: `iOS 18.0 / macOS 15.0 /
watchOS 11.0` (add `visionOS 2.0` if ever enabled). The current skill default
(iOS 18 / watchOS 10 / macOS 14) is an incoherent cohort and should be
corrected, not copied.**
Evidence & reasoning:
- Adoption (Apple's own figures, measured June 2026): iOS 26 = **79%** of all
  active iPhones and 86% of iPhones introduced in the last four years; iOS 18 =
  **14%**; earlier = **7%** [S8]. So an iOS 18.0 floor reaches ~**93%** of
  active iPhones; an iOS 26.0 floor reaches ~79%.
- Cohort coherence: iOS 18 / macOS 15 (Sequoia) / watchOS 11 / visionOS 2 all
  shipped Sept 2024. watchOS 10 and macOS 14 are the *iOS 17* cohort — pairing
  them with an iOS 18 floor buys nothing (no user is on watchOS 10 with an
  iOS 18 phone in meaningful numbers) and costs us every watchOS 11 / macOS 15
  API for free.
- Nothing in contracts §4 needs iOS 26: `@Observable` (17), SwiftData (17),
  ActivityKit (16.1), `ControlWidget` (18), App Intents + `AppShortcutsProvider`
  (16/18) are all ≤18. Liquid Glass renders automatically on OS-26 devices
  because we build against the 26 SDK; the 18.0 floor only affects older devices.
- Offer a documented `deployment` preset in `answers.example.yaml`:
  `stable` (18/15/11, default) and `modern` (26/26/26) for apps that want to
  hard-adopt OS-26-only design APIs.
Confidence: **high** on the coherence argument and the adoption numbers;
**medium** on 18-vs-26 as a *preference* (it is a product call, not a fact —
Fable/Pierce may reasonably prefer 26 for a greenfield template).

**V6. macOS 26 `MenuBarExtra` `setImage:` recursion: no public evidence it was
fixed, and no public evidence of the bug at all outside Pennywise's own
CHANGELOG. Recommendation: the template should not ship a menu-bar surface in
v1; if one is added, use `NSStatusItem`.**
Evidence: Pennywise `CHANGELOG.md` (2026-05-07 post-EE entry) records "SwiftUI
`MenuBarExtra` was hitting `setImage:` infinite recursion on macOS 26 Tahoe;
replaced with manual `NSStatusItem` via `MacAppDelegate`". Four separate
searches across Apple Developer Forums, macOS 26.3/26.4/26.4.1/26.5/26.5.2
release-note round-ups and MacRumors threads surfaced **no** matching report and
**no** fix note [S11][S12]. This is consistent with a Pennywise-specific trigger
(its menu-bar title is driven by a 1 Hz `Timer` + Combine `MergeMany`, i.e. a
high-frequency label mutation) rather than a universal `MenuBarExtra` defect.
Secondary point: even without the bug, `NSStatusItem` is the better default for
a *template* — it is the only way to get left/right-click discrimination,
explicit popover lifecycle, and custom `NSImage` rendering.
Contracts §3 does not list a menu-bar surface under the `mac` component, so the
cheapest correct answer is: **don't add one**; document the finding in
`MyAppMac/AGENTS.md` as a known-hazard note so the first person who reaches for
`MenuBarExtra` re-tests it deliberately.
Confidence: **low** that the bug is still live (unverifiable from here);
**high** that "no MenuBarExtra in v1 + hazard note" is the right template call.

**V7. API deltas since 2026-06 (WWDC26 / OS 27 / Xcode 27 beta) are additive
and touch none of the frozen §4 contracts. The template must adopt none of
them in v1** (Xcode 27 is beta; submissions require Xcode 26 — V1).
Headline only; **R4 owns signatures**:
- **WidgetKit**: new `systemExtraLargePortrait` family (iOS/iPadOS/macOS 27);
  widgets configurable through App Intents + "dynamic styling" [S13].
- **App Intents**: `ExecutionTargets` (route an intent to the app, an App
  Intents extension, a WidgetKit extension, or a combination), `ValueRepresentation`,
  `EntityCollection` for large entity sets, `LongRunningIntent` for >30 s work
  [S13]. Relevant to §4.4 later — our three intents are short and app-targeted,
  so nothing changes now.
- **ActivityKit**: new Dynamic Island presentation style with more information
  density [S13]. §4.2 `ContentState` shape is unaffected.
- **StoreKit**: notable item is a Unity plug-in — irrelevant to us [S13].
- **SwiftData**: no headline API change surfaced; treat as stable [S13].
- **SwiftUI**: toolbar control (`visibilityPriority`, `toolbarOverflowMenu`,
  `topBarPinnedTrailing`, `toolbarMinimizeBehavior`), resizable iPhone apps and
  adaptive/hinge-state layout APIs [S3][S14].
- **Xcode 27**: Live Previews resize handles; two bundled Coding-Assistant
  skills ("SwiftUI Specialist", "What's New in SwiftUI") [S14].
Action for the template: add a one-line "OS 27 / Xcode 27 is beta — do not
adopt" note to `AGENTS.md` §Toolchain, and re-run this check at the Xcode 27 GA
(expected ~Sept 2026), which lands *after* v0.1.0.
Confidence: **medium-high** (secondary sources; Apple's own pages are session
videos/guides that don't summarize cleanly).

---

### Part B — xcodegen capability audit (the ADR-0006 contingency decision)

**V8. DECIDED: list-valued keys contributed from an included spec APPEND. They
do not replace. ADR-0006's design stands; the `# @component:<id>`-tagged-line
contingency is NOT needed and should be struck from the plan.**

Evidence — `Sources/ProjectSpec/SpecFile.swift` @ master, verbatim:

```swift
func merged(onto other: [Key: Value]) -> [Key: Value] {
    var merged = other
    for (key, value) in self {
        if key.hasSuffix(":REPLACE") {
            let newKey = key[key.startIndex..<key.index(key.endIndex, offsetBy: -8)]
            merged[Key(newKey)] = value
        } else if let dictionary = value as? [Key: Value], let base = merged[key] as? [Key: Value] {
            merged[key] = dictionary.merged(onto: base) as? Value
        } else if let array = value as? [Any], let base = merged[key] as? [Any] {
            merged[key] = (base + array) as? Value          // ← APPEND, not replace
        } else {
            merged[key] = value
        }
    }
    return merged
}
```

and the call site:

```swift
private func mergedDictionary(set mergedSpecPaths: inout Set<Path>) -> JSONDictionary {
    let path = basePath + filePath
    guard mergedSpecPaths.insert(path).inserted else { return [:] }
    return jsonDictionary.merged(onto:
        subSpecs
            .map { $0.mergedDictionary(set: &mergedSpecPaths) }
            .reduce([:]) { $1.merged(onto: $0) })
}
```

Docs agree: "if existing value and new value are both an array then add the new
value to the end of the array" [S15]. Precise semantics that follow from the
code (these are the facts wave agents need):

| Question | Answer |
|---|---|
| Root `targets.MyApp.dependencies: [A]` + component `…: [B]` | → `[B, A]`. Both present. Includes' items first, root's appended. |
| Multiple component files contributing to the same list | Concatenated in `include:` declaration order. |
| Scalar conflict (root vs include) | **Root wins** (`self` = root `jsonDictionary`, `other` = merged sub-specs). |
| Nested dicts | Recursive merge all the way down; root wins at the leaves. |
| Per-key merge override | `:REPLACE` suffix on any key at any depth → replace instead of merge (shipped since XcodeGen 1.2.0). |
| Per-include merge control | **None.** Only `enable:` (on/off). Merge policy is global + per-key. |
| Deduplication | **None.** `(base + array)` is a plain concatenation. |
| Same file included twice (diamond) | Merged **once** — `mergedSpecPaths` guard returns `[:]` the second time. Shared base fragments are therefore safe. |

Two rules for W1A follow directly:
- **One owner per dependency edge.** Because there is no dedup, two component
  files must never contribute the same `dependencies` entry — that yields a
  duplicated `PBXTargetDependency` / embed entry. (Dedup only happens when
  `options.transitivelyLinkDependencies: true`, which defaults to `false`.)
- **Root must not restate anything a component contributes**, since root wins on
  scalars and appends on lists.
Confidence: **high** (source + docs + the `:REPLACE` changelog entry agree).

**V9. CRITICAL, and currently wrong in our design: `relativePaths` defaults to
`true`, which will silently mis-resolve every path in
`xcodegen/components/*.yml`. Every include MUST use the object form with
`relativePaths: false`.**
Evidence — `SpecFile.swift`:
```swift
static let defaultRelativePaths = true
…
private init(include: Include, basePath: Path, relativePath: Path, …) throws {
    let basePath = include.relativePaths ? (basePath + relativePath) : basePath
    let relativePath = include.relativePaths ? include.path.parent() : Path()
```
and `resolvingPaths(...)` rewrites everything in `Project.pathProperties`:
`configFiles`, `options`, `targets`, `targetTemplates`, `aggregateTargets`,
`schemes`, `projectReferences`, `packages`, `localPackages`, `fileGroups`.
So a component file at `xcodegen/components/watch.yml` saying
`sources: [MyAppWatch]` resolves to `xcodegen/components/MyAppWatch` — a path
that does not exist, producing a confusing "missing source" error (or, worse,
silence if someone sets `optional: true`). With `relativePaths: false`, basePath
stays the root spec's directory and `relativePath` is reset to empty, so
`resolvingPaths` short-circuits and paths are taken verbatim relative to the
repo root — which is what every other file in this repo assumes.
Note the string form (`- xcodegen/components/watch.yml`) always gets the
default `true`. There is no way to set it once globally.
Confidence: **high**.

**V10. `include.enable` is a first-class env-var-driven switch, and disabled
includes are never read from disk.**
Evidence: `includes.filter(\.enable)` runs *before* any `SpecFile(include:)` is
constructed, so the file for a disabled include need not exist. `enable` accepts
a YAML bool or a string-boolean (`(dictionary[key] as? NSString)?.boolValue`),
and `${VAR}` expansion is fed the **entire process environment**
(`ProjectCommand.swift`: `let variables = disableEnvExpansion ? [:] :
ProcessInfo.processInfo.environment`; `--no-env` / `-n` disables).
Two consequences worth acting on:
1. **Prune is fail-soft.** Even if a generated repo's `include:` line survives
   deletion of its component file, we can make it non-fatal. Better: our
   `verify.py` should assert the *pair* (file present ⇔ include line present).
2. **The 6-config `verify-macos` matrix has a cheaper mode.** Env-gated includes
   (`enable: ${MYAPP_COMPONENT_WATCH}`) can toggle target sets without running
   the generator. This does *not* replace real combo generation (Swift marker
   blocks + file deletion + plist edits still need `generate.py`), but it is a
   fast smoke rung and a debugging aid. Recommend **not** shipping env-gated
   includes in generated repos (they'd leave dead component files in a shipped
   app repo), and considering them only for the template's own CI.
Confidence: **high** on mechanics; **medium** on whether to use (2).

**V11. `configFiles` wiring is fine as designed, but xcconfig loses to
`settings:`, and that is a live footgun for ADR-0007.**
Evidence: `configFiles` exists at project level and per target, as a
`config-name → path` map [S15]; being a map it deep-merges across includes, so a
component may add a per-config xcconfig without clobbering. `settings:` merge
order inside xcodegen is `groups` → `base` → `configs`, and simple key maps are
**silently ignored** if any of `groups`/`base`/`configs` is present [S15]. But
above all of that sits Xcode's own precedence: an `.xcconfig` is the *lowest*
layer — a target/project build setting of the same name in the `.pbxproj`
overrides it.
→ Therefore `Config/Versions.xcconfig` only works if **`MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` appear nowhere in `project.yml` or any component
file**, and `Config/Shared.xcconfig` only works if `DEVELOPMENT_TEAM` appears
nowhere. Pennywise's failure mode was the mirror image (versions as YAML
literals patched by awk); ours would be quieter and worse — a stale hardcoded
version silently winning over CI's xcconfig.
Also relevant: `options.disabledValidations: [missingConfigFiles, missingConfigs,
missingTestPlans]` exists precisely for "generate in a context where these files
aren't present" — useful for pruned combos and for any structural check that
runs before `make bootstrap` writes `Versions.xcconfig`.
Confidence: **high**.

**V12. `options.bundleIdPrefix` is actively dangerous for this project and
should be removed from contracts §6.**
Evidence: "any target that doesn't have a `PRODUCT_BUNDLE_IDENTIFIER` (via all
levels of build settings) will get an autogenerated one by combining
`bundleIdPrefix` and the target name: `bundleIdPrefix.name`. The target name
will be stripped of all characters that aren't alphanumerics, hyphens, or
periods. Underscores will be replaced with hyphens." [S15]
With `bundleIdPrefix: com.example`, a target named `HomeWidget` that is missing
its explicit ID gets `com.example.HomeWidget` — **not** the required
`com.example.myapp.homewidget`. That violates contracts §2's "extension bundle
IDs = immediate host ID + exactly one segment" rule and reproduces exactly the
ITMS-90347 class of failure Pennywise already hit (`mac.widget` →
`macwidget`). Because the generated value is *plausible*, the mistake survives
generation and dies at upload.
Recommendation: **omit `bundleIdPrefix` entirely**, set explicit
`PRODUCT_BUNDLE_IDENTIFIER` on all 10 targets, and add a Linux lint asserting
(a) every target declares one and (b) every extension's ID equals its host's ID
plus exactly one dot-segment. A missing ID then fails loudly instead of
resolving to something wrong.
Confidence: **high**.

**V13. `targetTemplates` / `schemeTemplates` use the *same* merge engine, so
they compose with `include:` exactly as ADR-0006 hopes — with one naming
gotcha.**
Evidence — `Sources/ProjectSpec/Template.swift`: templates are collected
recursively (a template may itself list `templates:`), merged left-to-right via
the same `merged(onto:)`, then the concrete target/scheme is merged **on top**,
then `${target_name}` / `${scheme_name}` is expanded, then `templateAttributes`
are expanded. `Project.resolveProject` runs
`resolveMultiplatformTargets → resolveTargetTemplates → resolveSchemeTemplates →
resolveMultiplatformTargets` on the **already-include-merged** dictionary, so a
component file may define a target that references a template declared in the
root spec. `:REPLACE` works inside templates too.
Gotcha: env expansion (`${...}`) runs at *load* time, template-attribute
expansion runs *after* merge, and both use the same `${name}` syntax. An
environment variable whose name collides with a `templateAttributes` key wins
and the attribute is never applied. → use distinctive attribute names
(`tmplHostBundleId`, not `PRODUCT_NAME`).
Recommendation: two templates carry most of contracts §2's boilerplate —
`Extension` (`SKIP_INSTALL: YES`, `PRODUCT_BUNDLE_IDENTIFIER:
${tmplHostBundleId}.${tmplIdSegment}`, `CODE_SIGN_ENTITLEMENTS`,
`GENERATE_INFOPLIST_FILE`) and `MacTarget` (hardened runtime + sandbox).
And one `schemeTemplate` for the per-platform test/build shape.
Confidence: **high**.

**V14. Test plans: XcodeGen references `.xctestplan` files but does not
generate them.**
Evidence: "For now test plans are not generated by XcodeGen and must be created
in Xcode and checked in, and then referenced by path… If the test targets are
added, removed or renamed, the test plans may need to be updated in Xcode."
Shape: `schemes.<Name>.test.testPlans: [{path, defaultPlan}]`, supported since
2.29.0 [S15][S16].
Consequence for a *pruning* template: an `.xctestplan` is a JSON file with a
`testTargets` array containing `containerPath`/`identifier`/`name` triples. If
we ship one, `prune.py` must edit it (JSON — trivial) *and* combos that remove
a test target must not orphan it. Cheapest v1 answer: **ship no `.xctestplan`**;
express test selection through `schemes.*.test.targets` (which xcodegen *does*
generate and which merges additively from component files). Revisit if/when we
want per-configuration test runs.
Confidence: **high**.

**V15. `packages:` present-but-null is a real parse failure — contracts §2's
gotcha is correct.**
Evidence — `Project.swift`:
```swift
if jsonDictionary["packages"] != nil {
    packages = try jsonDictionary.json(atKeyPath: "packages", invalidItemBehaviour: .fail)
} else { packages = [:] }
```
A `packages:` key whose only content is comments parses to `nil` *value* but a
present *key* → `.fail`. Keep the key fully commented out, header included.
Confidence: **high**.

**V16. Pin the generator: `options.minimumXcodeGenVersion: '2.46.0'`.**
Evidence: the option exists and is checked before generation
(`try project.validateMinimumXcodeGenVersion(version)` in `GenerateCommand`);
current release is 2.46.0 [S16][S17]. Our design leans on `include` merge order,
`:REPLACE`, `relativePaths`, `optional`, `buildToolPlugins` — a template that
silently generates a wrong project under XcodeGen 2.29 is a bad template.
Pair it with a documented `brew install xcodegen` line and a Makefile
`check-tools` rung.
Confidence: **high**.

---

## Spec deltas

Exact edits, quoted. All are to `specs/_build/contracts.md` unless noted.

### D1 — §6, include syntax (from V9). **Blocking; W1A cannot ship without it.**

Replace:

> - Root `project.yml`: `name`, `options` (incl. `bundleIdPrefix: com.example`,
>   deployment targets, `createIntermediateGroups`), `settingGroups`,
>   `targetTemplates` (extension shape), `configFiles` wiring, `packages` (commented
>   until needed), always-on targets (MyApp, MyAppTests, MyAppUITests), top-level
>   `schemes`, and `include:` list of component files.

with:

> - Root `project.yml`: `name`, `options` (`minimumXcodeGenVersion: '2.46.0'`,
>   deployment targets, `createIntermediateGroups`, `disabledValidations:
>   [missingConfigFiles]`; **no `bundleIdPrefix`** — see below), `settingGroups`,
>   `targetTemplates` (extension shape) + `schemeTemplates`, `configFiles`
>   wiring, `packages` (commented until needed — the key itself must be
>   commented out, not left with a null value), always-on targets (MyApp,
>   MyAppTests, MyAppUITests), top-level `schemes`, and an `include:` list of
>   component files.
> - **Every `include:` entry MUST use the object form with
>   `relativePaths: false`.** The string form defaults to `relativePaths: true`,
>   which re-roots every path in the included file at that file's own directory
>   (`xcodegen/components/` here) and breaks all `sources`, `configFiles`,
>   `entitlements`, `info`, `schemes` and `packages` paths. Canonical shape:
>   ```yaml
>   include:
>     - path: xcodegen/components/mac.yml
>       relativePaths: false
>     - path: xcodegen/components/watch.yml
>       relativePaths: false
>   ```
> - **No `options.bundleIdPrefix`.** Every target declares an explicit
>   `PRODUCT_BUNDLE_IDENTIFIER`. `bundleIdPrefix` would auto-generate
>   `com.example.HomeWidget` for any target that forgot one — plausible, wrong,
>   and an ITMS-90347 rejection. A missing ID must fail loudly instead.
>   `verify.py` asserts: every target has an explicit ID, and every extension's
>   ID is its host's ID plus exactly one dot-segment.

### D2 — §6, resolve the R2 contingency (from V8). **Removes an open risk.**

Replace:

> - R2 MUST verify include deep-merge semantics for list-valued keys
>   (`targets.MyApp.dependencies` contributed from a component file). Contingency
>   if lists don't merge additively: those specific lines live in root project.yml
>   tagged `# @component:<id>` and prune removes tagged lines. No other yml
>   splicing exists.

with:

> - **RESOLVED (R2).** XcodeGen merges included specs additively: dictionaries
>   recurse, **arrays concatenate** (`merged[key] = (base + array)` in
>   `Sources/ProjectSpec/SpecFile.swift`), and scalars are replaced. The root
>   spec is merged *on top* of the reduced includes, so root wins scalar
>   conflicts and root's array items land *after* the includes'. A component
>   file contributing `targets.MyApp.dependencies: [{target: MyAppWatch}]`
>   therefore appends. **The `# @component:<id>` tagged-line contingency is
>   withdrawn — no yml splicing of any kind exists.**
>   Constraints that follow:
>   - There is **no deduplication**. Exactly one component file may contribute
>     any given dependency edge, source entry, or scheme-target entry.
>   - Root must not restate anything a component contributes.
>   - Per-key override is `:REPLACE` (suffix on the key, any depth) — reserved
>     for emergencies; v1 uses none.
>   - A spec included twice is merged once (path-set guard), so shared fragments
>     between component files are safe.

### D3 — §6, xcconfig precedence guard (from V11)

Append to the `Config/Versions.xcconfig` bullet:

> An `.xcconfig` is the lowest layer of Xcode's build-setting precedence: any
> `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` / `DEVELOPMENT_TEAM` written
> into `project.yml` (or a component file, or a `settingGroup`) **silently
> overrides the xcconfig**. `verify.py` therefore greps the whole
> `xcodegen/` + `project.yml` surface and fails if any of those three keys
> appears outside `Config/*.xcconfig`.

### D4 — §9, deployment defaults (from V5)

Replace:

> ```yaml
> deployment:                  # floors; defaults per R2
>   ios: "18.0"
>   macos: "14.0"
>   watchos: "10.0"
> ```

with:

> ```yaml
> deployment:                  # floors; R2-verified defaults (Aug 2026)
>   ios: "18.0"                # ~93% of active iPhones (iOS 26=79%, 18=14%)
>   macos: "15.0"              # same Sept-2024 cohort as iOS 18
>   watchos: "11.0"            # same Sept-2024 cohort as iOS 18
> ```
> The three floors are one OS cohort by construction; `answers.schema.json`
> warns if they are mixed across cohorts. A documented `modern` preset
> (`26.0/26.0/26.0`) exists for apps that hard-adopt OS-26 design APIs.
> Build SDK is always the latest stable Xcode's (26.6 as of 2026-08-02);
> App Store submission has required Xcode 26 + the 26-line SDKs since
> 2026-04-28.

### D5 — new §6 sub-bullet, toolchain pins (from V1/V2/V2b/V3)

Add to §6:

> - **Toolchain pins (as of 2026-08-02).** Xcode **26.6** (17F113, Swift 6.3) is
>   both floor and ceiling — App Store submissions require Xcode 26, and Xcode 27
>   is beta. `SWIFT_VERSION: '6.0'` (a *language mode*; there is no 6.2/6.3
>   value). Every target also sets Xcode 26's new-project defaults:
>   `SWIFT_APPROACHABLE_CONCURRENCY: YES` and
>   `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`. XcodeGen pinned via
>   `options.minimumXcodeGenVersion: '2.46.0'`.

### D6 — ADR-0003, runner + destination specifics (from V3/V3b/V3c/V4)

Add a "Runner specifics (R2-verified 2026-08-02)" section to
`docs/adr/0003-ci-posture.md`:

> - `verify-macos.yml` runs on **`macos-26`** (arm64; `macos-latest` since June
>   2026). `macos-14` is fully unsupported after 2026-11-02; `macos-15`/
>   `macos-15-intel` are legacy-only. Xcode is pinned with
>   `sudo xcode-select -s /Applications/Xcode_26.6.app` — a plain shell step, so
>   no third-party action needs SHA-pinning for this.
> - The image preinstalls Xcode 26.0.1 → 26.6 (26.6 default), fastlane 2.237.0
>   and SwiftFormat 0.62.1. It does **not** preinstall `xcodegen` or
>   `swiftlint`; the workflow runs `brew install xcodegen xcbeautify` and
>   `bundle install` against the committed `Gemfile.lock`.
> - **Simulator names are image-version-coupled and must not be hardcoded
>   blindly.** `iPhone 15` and `Apple Watch Series 9 (45mm)` do not exist on this
>   image. Defaults: `DEVICE ?= iPhone 17`,
>   `WATCH_DEVICE ?= Apple Watch Series 11 (46mm)`. `make build*` uses
>   `-destination 'generic/platform=iOS Simulator'` (no device needed for a
>   build); only `test`/`ui-test` name a device, resolved through
>   `scripts/apple/pick-simulator.sh` (`xcrun simctl list devices available
>   --json`, newest-iPhone fallback) with the Make var as an override.

### D7 — ADR-0006, record the resolved contingency (from V8/V9/V12)

Replace the ADR-0006 "Consequences" bullet:

> - If R2 finds include merging insufficient for dependency edges, only the
>   tagged-line contingency activates; the ADR stands.

with:

> - **R2 verified include merging at source (XcodeGen 2.46.0): arrays
>   concatenate, dicts recurse, root wins scalars. The tagged-line contingency
>   is withdrawn.** Two constraints were discovered and are now part of the
>   design: every `include:` uses the object form with `relativePaths: false`
>   (the default `true` re-roots all paths at the component file's directory),
>   and `options.bundleIdPrefix` is *not* used (it would auto-generate wrong,
>   plausible extension bundle IDs — ITMS-90347).

### D8 — §5/§3, capability components lose their .yml files (from A3 below)

Optional but recommended; append to §6:

> - Capability components that add **no target** (`swiftdata`, `store`,
>   `account`, `health`) need no `xcodegen/components/<id>.yml` at all. Their
>   source directories are declared once in the root spec as
>   `{ path: Shared/Capabilities/<X>, optional: true }`, and the umbrella
>   `Shared` source entry carries `excludes: ["Capabilities/**"]` so files are
>   never double-referenced. Pruning such a component is then exactly
>   `rm -rf Shared/Capabilities/<X>` plus its marker blocks — zero YAML edits.
>   Component `.yml` files exist only for the six target-bearing components
>   (`mac`, `watch`, `complications`, `widgets-home`, `widget-mac`,
>   `live-activity`, `nse`).

---

## Capability audit

Decision-10 / ADR-0006 standing sub-task: native capabilities of the tools in
this domain that our current design under-uses, and things we plan to hand-roll
that a tool already does.

### A. XcodeGen — under-used natives

| # | Capability | Status in our design | Recommendation |
|---|---|---|---|
| A1 | `options.minimumXcodeGenVersion` | absent | **Adopt.** `'2.46.0'`. We depend on merge semantics that older versions may not have. |
| A2 | `:REPLACE` per-key merge override | absent | Document as the escape hatch; use none in v1. Knowing it exists prevents a future splice engine. |
| A3 | `sources[].optional: true` | absent | **Adopt** for `Shared/Capabilities/*` (see D8). Turns 4 of 11 components into pure file-deletion with no YAML at all. |
| A4 | `sources[].excludes` / `includes` (bash-4 globstar) | absent | **Adopt** on the umbrella `Shared` entry to prevent double-referencing capability dirs. |
| A5 | `schemeTemplates` | absent (only `targetTemplates` planned) | **Adopt.** Every component adds scheme entries; a template collapses the repetition. |
| A6 | `options.preGenCommand` / `postGenCommand` | we plan Makefile wrapping | **Adopt `preGenCommand`** for `scripts/apple/generate-build-info.sh` so `BuildInfo.swift` is fresh even when someone runs bare `xcodegen`. Caveat: skipped when `--use-cache` short-circuits. |
| A7 | `xcodegen generate --use-cache` / `--cache-path` | absent | **Adopt** in Makefile `regenerate`. Free no-op when nothing changed. |
| A8 | `options.disabledValidations` | absent | **Adopt** `[missingConfigFiles]` so a fresh clone can generate before `make bootstrap` writes `Versions.xcconfig`. Add `missingTestPlans` only if we ever ship one. |
| A9 | `fileGroups` | absent | **Adopt.** Put `Makefile`, `Config/*.xcconfig`, `fastlane/`, `README.md`, `AGENTS.md` in the Xcode navigator. Pure ergonomics, one line. |
| A10 | `info:` / `entitlements:` plist generation from YAML (+ `--only-plists`) | we hand-maintain 10 Info.plists + 8 entitlements and plan `plistlib` edits in `prune.py` | **Partially adopt — Fable's call.** Generating `.entitlements` from YAML would put the App Group string in component files and delete `prune.py`'s plistlib path entirely. Cost: Xcode's Signing & Capabilities editor writes the on-disk file, and the next `xcodegen generate` silently clobbers it. Recommendation: generate **extension** Info.plists (pure `NSExtension` boilerplate) from YAML; keep host-app Info.plist and all `.entitlements` as checked-in files (Xcode-editable, matches Apple's mental model); `PrivacyInfo.xcprivacy` must stay a file regardless (it is a bundled resource, not a managed plist). Net: `prune.py` still needs plistlib, but for far fewer keys. |
| A11 | `type: syncedFolder` + `explicitFolders` (Xcode 16 buildable folders) | absent | **Considered, rejected for v1.** Would end "regenerate after adding a file" — but 10 targets share `Shared/`, and per-target membership then lives in `PBXFileSystemSynchronizedBuildFileExceptionSet`, which is exactly the surface our pruning would have to manipulate. Revisit post-v1. |
| A12 | `supportedDestinations` (one multiplatform target) + `destinationFilters` / `inferDestinationFiltersByPath` | absent; §2 has separate `MyApp` + `MyAppMac` | **Considered, rejected for v1** — the Mac target has divergent UI and different entitlements, and app targets cannot use the watchOS destination (docs are explicit). But **adopt `inferDestinationFiltersByPath`** inside `Shared/` if any platform-specific file lands there; it beats `#if os()` sprawl. |
| A13 | `buildToolPlugins` + `packages` | `packages` commented out; plugins unmentioned | Note only. This is the native home for a future SwiftLint/swift-format SPM plugin — no `preBuildScripts` shelling out. |
| A14 | `aggregateTargets` | absent | Note only. The native "run once per build, not per target" hook if `generate-build-info` ever needs to be in-build rather than pre-gen. |
| A15 | `scheme.test.gatherCoverageData` + `coverageTargets` | absent; coverage would be an xcodebuild flag | **Adopt** if we want coverage — configuring it in the scheme means `make test` and Xcode's Cmd-U agree, instead of coverage existing only on the CLI. |
| A16 | `options.groupOrdering` / `groupSortPosition` / `createIntermediateGroups` | only `createIntermediateGroups` planned | Cheap: `groupOrdering` makes the navigator legible for a template people read. |
| A17 | `breakpoints:` (shared breakpoints in the project) | absent | Skip. Noted for completeness. |
| A18 | `options.schemePathPrefix` | absent | Note only — needed the day this becomes a workspace (default `"../../"` is correct for a bare `.xcodeproj`). |

### B. xcodebuild / Xcode CLI — under-used natives

| # | Capability | Status | Recommendation |
|---|---|---|---|
| B1 | `-destination 'generic/platform=iOS Simulator'` | not used; skill hardcodes device names | **Adopt for every build-only invocation.** Removes device-name fragility from most calls — the single highest-leverage fix from V4. |
| B2 | `xcrun simctl list devices available --json` / `xcodebuild -showdestinations` | not used | **Adopt** in `scripts/apple/pick-simulator.sh`. Discover, don't hardcode. |
| B3 | `-resultBundlePath` + `xcrun xcresulttool` | partially (skill's test.yml sets the path but nothing reads it) | **Adopt** — parse the xcresult into a CI job summary instead of scraping xcodebuild stdout. |
| B4 | `-retry-tests-on-failure`, `-parallel-testing-enabled`, `-test-timeouts-enabled` | absent | Note; adopt `-retry-tests-on-failure 2` for UI tests, which are the flaky rung. |
| B5 | `-skipPackagePluginValidation` / `-skipMacroValidation` | absent | Note — required the day we add an SPM macro or plugin in CI. |
| B6 | `xcodebuild -exportArchive` vs fastlane `gym` | ADR-0002 already routes through fastlane | No change; recorded so nobody re-hand-rolls it. |
| B7 | `xcrun notarytool` | skill already prefers it over `altool` | No change (correct already). |
| B8 | `swift-format` shipped in the Swift 6 toolchain | unknown; skill/skeleton assume external formatters | **Open item for the Phase-5 Mac loop:** verify `xcrun swift-format --version` on the runner before adding any `brew install swift-format`. The image *does* preinstall Nick Lockwood's SwiftFormat 0.62.1 (a different tool) and does *not* preinstall SwiftLint. Confidence low — do not encode either assumption until checked on a Mac. |

### C. Things we planned to hand-roll that a tool already does

1. **`# @component:<id>` tagged-line removal from `project.yml`** — withdrawn
   (V8). XcodeGen's additive merge already does it.
2. **plistlib editing of entitlements in `prune.py`** — largely replaceable by
   XcodeGen's `entitlements:` generation (A10). Recommend shrinking rather than
   deleting, for the Xcode-clobber reason.
3. **`.yml` files for capability-only components** — replaceable by
   `optional: true` sources (A3/D8).
4. **Hardcoded simulator device names in Makefile/CI** — replaceable by
   `generic/platform=…` and `simctl list --json` (B1/B2).
5. **A per-target `preBuildScript` for build-info generation** — replaceable by
   `options.preGenCommand` (A6).
6. **A "did anything change?" guard around `xcodegen generate` in the Makefile**
   — replaceable by `--use-cache` (A7).
7. **`maxim-lobanov/setup-xcode` as a SHA-pinned dependency** — replaceable by
   one `sudo xcode-select -s` line (V3).

---

## Sources

- [S1] Xcode version index (release dates, Swift version, bundled SDKs, min
  macOS): https://mungomash.com/software/xcode/versions/ — page states last
  updated July 2026; newest entry Xcode 26.6 (17F113), 2026-06-25, Swift 6.3.
  Fetched 2026-08-02.
- [S2] "Swift 6.3 Released", Swift.org blog, 2026-03-24:
  https://www.swift.org/blog/swift-6.3-released/ ; blog index:
  https://www.swift.org/blog/ (newest release post = 6.3). Fetched 2026-08-02.
- [S3] "What's new for Apple developers", Apple:
  https://developer.apple.com/whats-new/ — currently fronts Xcode 27 beta and
  the OS 27 line. Fetched 2026-08-02.
- [S4] `actions/runner-images` macOS 26 arm64 image readme, image version
  20260728.0273.1 (macOS 26.5.2 / 25F84):
  https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-arm64-Readme.md
  — Xcode table with paths, simulator device lists, tool inventory
  (fastlane 2.237.0, SwiftFormat 0.62.1, Homebrew 6.0.13; no xcodegen, no
  swiftlint). Fetched 2026-08-02.
- [S5] "macos-26 is now generally available for GitHub-hosted runners", GitHub
  Changelog, 2026-02-26:
  https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/
- [S6] "[macOS] macos-latest label will use macos-26 in June 2026",
  actions/runner-images issue #14167:
  https://github.com/actions/runner-images/issues/14167 ; and "Upcoming changes
  to macOS hosted runners" (macos-15-intel until Aug 2027, x86_64 retired after
  macOS 15 image, Fall 2027), GitHub Changelog 2025-07-11:
  https://github.blog/changelog/2025-07-11-upcoming-changes-to-macos-hosted-runners-macos-latest-migration-and-xcode-support-policy-updates/
- [S7] "[macOS] The macOS 14 Sonoma based runner images will begin deprecation
  on July 6th and will be fully unsupported by November 2nd",
  actions/runner-images issue #13518:
  https://github.com/actions/runner-images/issues/13518
- [S7b] "[macOS] Default Xcode on macOS 26 Tahoe will be set to Xcode 26.6 on
  2026.07.21", actions/runner-images issue #14344:
  https://github.com/actions/runner-images/issues/14344
- [S8] iOS 26 adoption, Apple figures measured June 2026 (79% of all active
  iPhones, 86% of last-four-years iPhones, iOS 18 = 14%, earlier = 7%):
  https://www.iclarified.com/101140/ios-26-adoption-reaches-86-on-recent-iphones-79-overall-chart
  and https://www.macrumors.com/2026/06/09/ios-26-adoption-stats-wwdc/
- [S9] Xcode 26 / SDK 26 mandatory for App Store submissions from 2026-04-28:
  https://developer.apple.com/news/?id=6lxhtioi and
  https://developer.apple.com/forums/thread/806141
- [S10] Xcode 26 new-project concurrency defaults
  (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
  `SWIFT_APPROACHABLE_CONCURRENCY = YES`):
  https://www.donnywals.com/setting-default-actor-isolation-in-xcode-26/ and
  https://www.massicotte.org/blog/mainactor-by-default/
- [S11] Pennywise `CHANGELOG.md`, entry dated 2026-05-07 ("Post-EE work"):
  `/home/user/pennywise-apple-universal/CHANGELOG.md` lines ~30–34.
- [S12] Negative result — four searches over Apple Developer Forums, macOS Tahoe
  26.3/26.4/26.4.1/26.5/26.5.2 release-note round-ups and MacRumors threads
  found no `MenuBarExtra` / `setImage` recursion report or fix. Representative:
  https://developer.apple.com/documentation/macos-release-notes/macos-26_5-release-notes
- [S13] WWDC26 session/guide coverage — WidgetKit foundations
  (https://developer.apple.com/videos/play/wwdc2026/277/), "Discover new
  capabilities in the App Intents framework"
  (https://developer.apple.com/videos/play/wwdc2026/345/), WWDC26 iOS guide
  (https://developer.apple.com/wwdc26/guides/ios/).
- [S14] WWDC26 SwiftUI guide (https://developer.apple.com/wwdc26/guides/swiftui/)
  and "What's new in SwiftUI" WWDC26
  (https://developer.apple.com/videos/play/wwdc2026/269/).
- [S15] XcodeGen `Docs/ProjectSpec.md` @ master, fetched 2026-08-02:
  https://raw.githubusercontent.com/yonaskolb/XcodeGen/master/Docs/ProjectSpec.md
  (Include, Options, Configs, Setting Groups, Settings, Target, Sources, Config
  Files, Plist, Build Tool Plug-ins, Target Template, Scheme, Test Plan,
  Scheme Template sections).
- [S16] XcodeGen `CHANGELOG.md` @ master (latest release 2.46.0; `:REPLACE` since
  1.2.0; `configFiles` since 1.2.0; `targetTemplates` since 2.3.0;
  `templateAttributes` since 2.2.0; test-plan references since 2.29.0;
  `buildToolPlugins` since 2.37.0/2.38.0; scheme management since 2.34.0):
  https://github.com/yonaskolb/XcodeGen/blob/master/CHANGELOG.md
- [S17] XcodeGen source @ master, fetched and read in full 2026-08-02:
  `Sources/ProjectSpec/SpecFile.swift` (merge engine, `Include` parsing,
  `relativePaths`/`enable`, path resolution, diamond guard),
  `Sources/ProjectSpec/Template.swift` (target/scheme template resolution),
  `Sources/ProjectSpec/Project.swift` (`pathProperties`, `resolveProject`,
  `packages` null-fail), `Sources/ProjectSpec/SpecLoader.swift`,
  `Sources/XcodeGenCLI/Commands/ProjectCommand.swift` (env→variables,
  `--no-env`), `Sources/XcodeGenCLI/Commands/GenerateCommand.swift`
  (`--use-cache`, `--only-plists`, `validateMinimumXcodeGenVersion`),
  `Sources/XcodeGenKit/PBXProjGenerator.swift` (dependency handling; dedup only
  under `transitivelyLinkDependencies`).
- [S18] `lang-swift-apple` skill @ 0.4.0 and `agentic-skeleton` skill, read from
  `/root/.claude/skills-src/` on 2026-08-02 (see `R2-skill-update-draft.md` for
  file:line citations).
