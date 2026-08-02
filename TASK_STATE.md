# Task: Build template-apple-swift v0.1.0

Status: in-progress
Owner: Fable (orchestrator) + Opus max-effort wave agents

## Context

Building Pierce's Apple-app template repo per the approved plan
(`/root/.claude/plans/template-apple-swift-is-a-new-stateful-orbit.md`, mirrored
in decisions at `docs/adr/0001`–`0009`). Superset walking-skeleton app
("Checkpoints" domain, `MyApp` identity) + onboarding wizard + deterministic
generator + fastlane release automation + full agentic layer (Serena-free).
Reference: `/home/user/pennywise-apple-universal`. Skills floor:
`lang-swift-apple` + `agentic-skeleton` (installed versions).
Construction contracts: `specs/_build/contracts.md` (FROZEN),
ownership: `specs/_build/file-ownership.md`.

## Slices

- [x] S0 — Groundwork: contracts, ownership map, ADRs 0001–0009, component
      registry skeleton, answers schema draft, TASK_STATE. (Fable)
- [x] S1 — Research wave: R1–R5 complete (5/5, 0 errors; deliverables in
      specs/_build/research/). Gate DONE 2026-08-02: all spec deltas applied,
      contracts.md FROZEN v1. Headlines: xcodegen lists concatenate
      (contingency withdrawn; relativePaths:false mandatory; bundleIdPrefix
      banned); produce needs Apple ID (bootstrap_asc split); gym needs xcargs
      threading + legacy export names; runner=macos-26/Xcode 26.6/iPhone 17;
      floors 18.0/15.0/11.0; op IS authed here (service account, agentic
      vault); spinnerVerbs+spinnerTipsOverride real at project scope;
      skeleton agents' tools: syntax defect (avoid).
- [x] S2 — Wave 1 superset app: W1A/W1B/W1C complete (3/3, 0 errors; 111
      files). Gate DONE 2026-08-02: junction-include refactor (account.yml /
      account-mac.yml / health.yml replace YAML markers — markers Swift-only),
      onSnapshot fan-out wiring, WatchLink mac exclusion, components.yaml
      updated, structural gate 0 FAIL. Resolutions:
      specs/_build/gate-w1-resolutions.md.
- [x] S3 — Wave 2 machinery: W2A/W2B/W2C/W2D/W2E complete (5/5, 0 errors).
      Gate DONE 2026-08-02: VERSION created (0.1.0); vibe.py schema-valid
      candidate paths; pre-compact hook renamed pre-compact-apple.sh
      (sync-safe); Versions.xcconfig untracked+gitignored (machine-written);
      check-no-serena guard added to ci-linux; APPLE_ID_AUTH capability fix;
      spinner corpus materialized (194 verbs + 37 tips, spinner-check green);
      onboard.md race → W2E superset ratified; make/*.mk partition ratified.
      RESULT: make ci-linux ALL 14 GATES PASS · generator pytest 113/113 ·
      all six combos generate+verify · nine fastlane lanes register ·
      statusline <300ms. Ratified divergences + answers:
      specs/_build/questions-w2*.md (gate notes inline).
- [x] S4 — Integration: DONE 2026-08-02. GitHub ci.yml run #4 GREEN
      (all 9 jobs: generator tests, 6 combo matrix, make ci-linux 14 gates,
      docs). Real-CI shakeout fixed: shellcheck severity calibration (-S
      warning; skeleton-verbatim auto-lint.sh untouchable per ADR-0008) and
      proved bump-per-commit live (0.1.1). apple-reviewer +
      xcode-build-debugger agents registered live in-session.
- [ ] S5 — Mac verification loop 🟡 in-progress — BLOCKED on dispatch
      permission: this session's GitHub integration lacks Actions:write
      (403 on workflow_dispatch). Pierce unblocks with EITHER
      `gh workflow run verify-macos.yml --repo rex/template-apple-swift \
      --ref claude/template-apple-swift-setup-b58nmp -f combo=all` from his
      machine, OR granting the Claude GitHub App Actions write. Fable polls
      for the run and drives compile failures to green with targeted fix
      agents (xcode-build-debugger + owners per failing file).
- [ ] S4 — Integration: cross-reference reconciliation, full Linux verification,
      version bump, CHANGELOG, push.
- [ ] S5 — Mac verification loop: verify-macos matrix → green (fix agents on
      failures).
- [ ] S6 — Finish: delete specs/_build, polish, propose v0.1.0 tag; deliver
      lang-swift-apple skill-update proposal + Pennywise security note.

## Risks

- Swift written blind on Linux (no compiler here) — mitigated by R4 SDK cribs,
  Pennywise-proven patterns, and the Phase-5 Mac loop.
- xcodegen include deep-merge semantics for list keys unverified — R2 decides;
  contingency = `# @component:` tagged lines in root project.yml.
- fastlane lane specifics (produce extension-ID coverage, cloud signing in CI)
  — R1 decides lane internals; lane NAMES are frozen.

## Done when

- Template repo ci.yml green (generator tests, 6 combo dry-runs, ci-linux).
- verify-macos matrix green across all 6 configs (build + test).
- Onboarding dry-run produces a repo whose own `make validate` passes on a Mac.
- Pierce receives skill-update proposal + security note; v0.1.0 tag proposed.

## Rules

- Follow standing directives: push every commit; no snowflake hacks; agents
  never git-mutate (Fable commits); unset VIBE fields = schema defaults.
- Pennywise is READ-ONLY reference.
- No Serena anywhere in this repo's shipped configuration.

## Handoff note

(rewritten at each phase gate; final rewrite ships as the post-onboarding
TASK_STATE template content)
