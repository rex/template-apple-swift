# Wave-1 gate resolutions (Fable, 2026-08-02)

Binding answers to `questions-w1{a,b,c}.md`. Wave-2 agents read this INSTEAD of
re-litigating those files. contracts.md §5/§6 and `template/components.yaml`
already reflect everything here.

1. **W1A Q3 (YAML markers) → REJECTED; junction includes instead.** The three
   `#`-form YAML marker blocks were replaced by capability fragments
   `xcodegen/components/{account,health}.yml` + junction
   `account-mac.yml` (included iff account ∧ mac). `components.yaml` gained an
   `includes:` map (file → required components); the generator keeps an include
   entry iff ALL requires are enabled. Markers are Swift-only, everywhere,
   forever. prune.py does NO yml content surgery — only file deletes +
   two-line include-entry removal.
2. **W1A Q1 — seven** target-bearing component ymls + three capability/junction
   fragments = ten include files. contracts §6 amended.
3. **W1A Q2 (generated plists) → ACCEPTED as built.** All Info.plist /
   .entitlements xcodegen-generated (gitignored); PrivacyInfo hand-authored ×8;
   test bundles use synthesized plists. components.yaml has NO plist-key maps
   anymore. verify.py asserts: App Group string exactly 8× across xcodegen
   YAML; every target has explicit PRODUCT_BUNDLE_IDENTIFIER; extension ID =
   host + one segment.
4. **W1A Q5 (empty AppIcon wells) → ACCEPTED for the template.** W2B's `beta`
   lane preflights icon presence (fail with pointer to onboarding docs); the
   onboarding record + template-guide list "drop a 1024 master icon" as a
   first-run step.
5. **W1A Q6 scheme names are API:** `MyApp`, `MyAppScreenshots` (snapshot +
   make ui-test), `MyAppMac`, `MyAppWatch`. W2B Snapfile uses MyAppScreenshots.
6. **W1B/W1C live-activity seam → RESOLVED at gate.** `CheckpointStore.onSnapshot`
   is now ALWAYS-ON (un-gated); MyAppApp assigns one fan-out closure whose
   INNER blocks are component-gated (live-activity → LiveActivityController.sync;
   watch → WatchLink.pushContext). Any subset strips to compiling code.
7. **W1C Q2 → AppDependencyManager/@Dependency stands; NO singleton on
   CheckpointStore.** (LiveActivityController.shared + WatchLink.shared remain —
   they're component-owned leaves.)
8. **W1C Q8 → mac.yml now excludes WatchLink.swift too** (belt: canImport
   guard; suspenders: exclusion).
9. **Watch mirroring semantics (v1, documented not changed):** each side runs a
   local store; the seam DEMONSTRATES WCSession (phone pushes context via
   onSnapshot fan-out; watch displays phone state row; watch actions act on its
   local store). A reconciling sync engine is intentionally out of scope —
   template-guide (W2D) documents this + the upgrade path.
10. **W1C Q1 (AGENTS.md ownership) →** W1C's three app-target AGENTS.md stand;
    extension dirs get NONE in v1; W2D's root AGENTS.md §12 index states both.
11. **W1C Q10 (interactive widget button) → deferred**, noted in template-guide
    as an upgrade recipe.
12. **W1C Q12 (NSE uses os.Logger directly) → ACCEPTED** (NSE pulls a thin
    Shared subset; Log.swift not among it).
13. **SnapshotHelper.swift (vendored, 315 lines) →** VIBE `architecture.exclude_globs`
    must include `UITests/MyAppUITests/SnapshotHelper.swift` (W2D).
14. **Spinner materialization sequencing:** W2D writes settings.json WITH
    placeholder `spinnerVerbs`/`spinnerTipsOverride` blocks; W2E writes the
    corpus .txt files + `scripts/sync_spinner_verbs.py` and does NOT touch
    settings.json; Fable runs the sync at Phase-4 integration. `make
    spinner-sync`/`spinner-check` (W2C) delegate to that script path.
15. **Generator CLI frozen (W2A):** `uv run template/generate.py
    --answers <file> [--dest DIR | --apply] [--dry-run]`; refuses when
    `template/` absent; `/onboard` (W2E→W2D command) invokes exactly this.
