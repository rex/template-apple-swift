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
- [ ] S1 — Research wave 🟡 in-progress — NEXT: dispatch R1–R5 (Opus max):
      R1 fastlane deep-dive · R2 toolchain currency + xcodegen capability audit
      + skill-update draft · R3 1Password op-wrapper .mcp.json · R4 SDK contract
      cribs · R5 Claude Code surfaces (spinner/statusline/skills). Gate: Fable
      freezes contracts v1.
- [ ] S2 — Wave 1 superset app: W1A structure / W1B Shared+Tests / W1C targets.
      Gate: Linux structural checks; Fable commits.
- [ ] S3 — Wave 2 machinery: W2A generator / W2B fastlane / W2C build+CI /
      W2D agentic / W2E fun layer. Gate: ci-linux + generator pytest + 6 combo
      dry-runs; Fable commits.
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
