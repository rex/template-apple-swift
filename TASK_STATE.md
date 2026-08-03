# Task: Build template-apple-swift v0.1.0

Status: complete
Owner: Fable (orchestrator) + Opus max-effort wave agents

## Context

Built Pierce's Apple-app template repo per the approved plan (mirrored in
`docs/adr/0001`–`0009`). Superset walking-skeleton app ("Checkpoints"
domain, `MyApp` identity) + onboarding wizard + deterministic generator +
fastlane release automation + full agentic layer (Serena-free). Reference:
`/home/user/pennywise-apple-universal` (read-only). Construction contracts
lived in `specs/_build/` — deleted at S6 as designed; git history
(pre-v0.8.0) preserves them. Their load-bearing rules live on in
`.claude/rules/swift.md`, `CONVENTIONS.md` and the ADRs.

## Slices

- [x] S0 — Groundwork: contracts, ownership map, ADRs 0001–0009, component
      registry skeleton, answers schema draft, TASK_STATE. (Fable)
- [x] S1 — Research wave: R1–R5 complete (5/5). Contracts FROZEN v1.
- [x] S2 — Wave 1 superset app: W1A/W1B/W1C complete (111 files).
- [x] S3 — Wave 2 machinery: W2A–W2E complete. make ci-linux ALL GATES ·
      pytest 113/113 · six combos generate+verify · nine fastlane lanes.
- [x] S4 — Integration: GitHub ci.yml run #4 GREEN (all 9 jobs).
- [x] S5 — Mac verification loop: DONE 2026-08-03 — verify-macos run #7
      (id 30778569907, sha 37994c2) ALL SIX JOBS GREEN: generate → verify →
      xcodegen → build (10 targets) → Swift Testing suites → XCUITest smoke
      (superset). Seven runs total; every compiler verdict became a Linux
      gate + a swift.md rule: bash-3.2 heredoc/mapfile (0.1.3) · extension
      isolation (0.3.0) · App Intents nonisolated-type ban (0.4.0) ·
      nonisolated witnesses / SE-0470 isolated-conformance ban (0.5.0) ·
      ActivityKit detached-task sends + hermetic App-Group tests (0.6.0) ·
      SwiftData group-container trap probe (0.7.0).
- [x] S6 — Finish: specs/_build deleted; docs re-pointed; final proposal +
      security note delivered; tag proposed (see Handoff).

## Risks

- (closed) All construction risks resolved by the green matrix. Remaining
  operational caveat: CI simulators are unsigned, so App-Group-dependent
  behavior (real SwiftData group store, cfprefsd suites) is proven only on
  signed local builds — gotcha row 13.

## Done when

- [x] Template repo ci.yml green (generator tests, 6 combo dry-runs, ci-linux).
- [x] verify-macos matrix green across all 6 configs (build + test + smoke).
- [x] Generated repos' own gates pass (every combo runs the same make chain).
- [x] Pierce received skill-update proposal + Pennywise security note.

## Rules

- Follow standing directives: push every commit; no snowflake hacks; agents
  never git-mutate (Fable commits); unset VIBE fields = schema defaults.
- Pennywise is READ-ONLY reference.
- No Serena anywhere in this repo's shipped configuration.

## Handoff note

Construction is COMPLETE at v0.8.0 (branch
`claude/template-apple-swift-setup-b58nmp`). Remaining clicks are Pierce's:

1. Merge the branch to `main` (fast-forward or squash — owner's choice;
   the repo is already public).
2. Flip **Settings → Template repository** so "Use this template" appears.
3. Tag the merged commit (suggest `v1.0.0` — the matrix is the release
   gate and it is green; `make bump-major` + tag, or tag v0.8.0 as-is).

For the next session in this repo: this file reverts to the un-onboarded
idle format at onboarding (`template/` regenerates it). Do not start
feature work here — `/onboard` is the only job in an un-onboarded tree.
