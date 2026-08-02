# Questions / notes — W2C (build system + CI)

Nothing here blocked me: everything is coded to `contracts.md` as written. These
are the rulings I want at the wave gate, plus the cross-partition facts Fable
needs for Phase-4 integration.

## Q1 — `make/*.mk` is a partition extension. Ratify or reject.

The Makefile does not fit in 400 lines once the skeleton contract targets, the
Apple verbs, the fastlane delegation and `ci-linux` are all real. Split by
responsibility:

```
Makefile           288  configuration + Apple verbs (bootstrap/build/test/audit)
make/help.mk        75  the hand-crafted help target
make/gates.mk      219  agentic-skeleton contract gates + versioning
make/release.mk     44  1:1 fastlane lane delegation (contracts §8)
make/ci.mk         166  ci-linux — every gate that runs without Xcode
```

`make/` is not named in `file-ownership.md`. It is unambiguously build-system,
so I claimed it, but: (a) confirm, and (b) W2D should list it in `MAP.md`.

## Q2 — `VERSION` does not exist. BLOCKING for the version gate.

`CHANGELOG.md` already carries a `0.1.0` entry and `VIBE.yaml` is wired, but
there is no `VERSION` file, so `make check-version-bumped` fails and
`scripts/apple/write-versions.sh` refuses to write `Config/Versions.xcconfig`
(which makes `make bootstrap` — and therefore every build target — stop).

It is a skeleton file, so it is W2D's or Fable's. The fix is one line:

```
echo 0.1.0 > VERSION
```

I created it while testing, verified the whole chain green with it, then
removed it again rather than write outside my partition.

## Q3 — two files fail `check-architecture` (not mine)

`make ci-linux` is red on exactly this:

```
✗ scripts/sync_spinner_verbs.py — 12 public entry points (4 over)   [W2E]
✗ template/tmpl/answers.py      — 10 public entry points (2 over)   [W2A]
```

Split, or add to `architecture.exclude_globs` in VIBE.yaml (which is where
resolution #13 already sends `SnapshotHelper.swift`). Either way it is W2A /
W2E / W2D's call, not a Makefile change.

## Q4 — `make spinner-check` is red until Fable runs `make spinner-sync`

Expected, per gate resolution #14: W2D wrote placeholder `spinnerVerbs` /
`spinnerTipsOverride` blocks, W2E wrote the 194-verb / 37-tip corpus, and the
sync happens at Phase-4 integration. `make spinner-sync` fixes it; the check
target reports the drift and names that fix. Flagging only so the red is not
mistaken for a defect.

## Q5 — `make verify` added as an alias (W2D's AGENTS.md promises it)

Root `AGENTS.md` §2 documents `make verify   # full gate chain — macOS only`,
which is not in contracts §8. Rather than let a documented command not exist, I
added `verify: check-if-the-agent-can-consider-this-task-completed` — a pure
alias, so the contract composition (`validate check-docs check-precommit test`)
is untouched. Confirm, or tell W2D to reword.

Same category, already reconciled with their doc: `make regenerate` (§9) and
`make ci-linux` "structure checks + template pytest suite" (§3) — `ci-linux`
now runs `template/verify.py` and the `template/tests` pytest suite, both
skipping cleanly once `template/` self-destructs.

## Q6 — I did NOT add `mac-testflight` / `certs` targets (answers W2B's Q5)

contracts §8 freezes seven Make targets. `mac_beta` and `certs` are documented
in `make help` as `bundle exec fastlane mac_beta | certs`. Say the word if you
want the eighth and ninth.

## Q7 — `Config/Versions.xcconfig` is committed *and* machine-written

`make bootstrap` rewrites it on every run (ADR-0007), so a clean checkout goes
dirty the first time anyone builds, and the completion gate's dirty-tree note
fires. Two ways out, both W1A's call:

- gitignore it — `project.yml` already sets `disabledValidations:
  [missingConfigFiles]` specifically so a fresh clone generates without it; or
- keep it committed and accept the churn (documented as machine-written).

Also: the header comment my script writes names `scripts/apple/write-versions.sh`
as the writer, so the first `make bootstrap` shows a comment diff as well as a
build-number diff. I left W1A's committed copy byte-for-byte untouched.

## Q8 — Xcode Cloud shallow clones (recorded, not a question)

`git rev-list --count HEAD` is a lie on a shallow clone, and Xcode Cloud clones
shallowly for most workflows. I did not change the frozen ADR-0007 formula:
`write-versions.sh` honors an explicit `CURRENT_PROJECT_VERSION` env override,
and `ci_scripts/ci_post_clone.sh` sets it from `CI_BUILD_NUMBER` **only when the
clone is actually shallow**, logging that it did. Full history still wins.

## Q9 — `WATCH_DEVICE` is declared but unused

ADR-0003 names `WATCH_DEVICE ?= Apple Watch Series 11 (46mm)` as a default, so
it is in the config block and in `make help`. Nothing consumes it: there is no
watchOS test bundle (`MyAppTests` is iOS-only), and `build-watch` uses a generic
destination. Keep it as the documented override for whoever adds watch tests,
or drop it from the Makefile?

## Note — upstream bug found in `lang-swift-apple/scripts/`

Both `audit-privacy-manifest.sh` and `audit-usage-descriptions.sh` do

```bash
set -euo pipefail
hits=$(grep -rEl "$pattern" ... | wc -l | tr -d ' ')
```

With `pipefail`, a no-match `grep` (exit 1) makes the whole pipeline exit 1, and
`set -e` kills the script mid-audit — it exits non-zero having audited nothing,
which looks like a real failure. My copies append `|| true` and say why. Worth
a line in the Phase-6 skill-update proposal.
