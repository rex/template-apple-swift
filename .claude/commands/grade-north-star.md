---
description: Grade this repo against the lang-swift-apple north-star standard and write the ADR.
argument-hint: (optional) axis to focus on, e.g. concurrency
allowed-tools: Agent, Read, Grep, Glob, Bash(ls:*), Write
model: opus
---

Grade this repo against the **lang-swift-apple north-star standard**$ARGUMENTS.

The skill is explicit that it is a grading rubric, not a lowest common
denominator: in a greenfield app every rule is the default, and where a repo
diverges the job is to nudge it toward the standard — not to lower the
standard to fit the repo. Grade accordingly. A template that ships the
divergence to every future app is worse than an app that has it once.

## 1. Delegate the reading

Spawn the **apple-reviewer** subagent (`Agent`) with this instruction:

> Grade the whole repository — not a diff — against the lang-swift-apple
> north-star standard at `/root/.claude/skills-src/lang-swift-apple`
> (`SKILL.md`, `AGENTS.md`, and the `references/` files relevant to each
> axis). Use the rubric-table output format. One row per axis. Be specific:
> cite file paths, and where this repo deliberately diverges, say whether the
> deviation is documented in an ADR or is simply undone work.

Axes to cover, at minimum:

| Axis | Anchor |
|---|---|
| Project shape | one xcodegen project, `.xcodeproj` never committed, targets per `contracts.md` §2 |
| Swift 6 concurrency | explicit `@MainActor` / `nonisolated` on every type, no `@unchecked Sendable` without justification |
| SwiftUI + state | `@Observable` only; no `ObservableObject` / `@Published` / `@StateObject` |
| Design tokens | `Theme.*` everywhere, zero hex literals or magic numbers in views |
| Persistence | `CheckpointPersisting` seam, SwiftData behind it, store is the only mutation path |
| Cross-process | `WidgetSync` as the single App Group bridge; 65 KB WCSession discipline |
| Extensions | `containerBackground`, host-vs-extension plist keys, bundle-ID arithmetic |
| Testing | Swift Testing (`@Test` / `#expect`), UITest + snapshot driver, what is actually covered |
| Compliance | Privacy manifests per bundle, usage strings, String Catalog instead of literals |
| Distribution | fastlane lane surface, Xcode Cloud / GitHub Actions posture, version contract |
| Modern integration | App Intents + AppShortcuts, TipKit, MetricKit, StoreKit 2, Sign in with Apple |
| Agent layer | AGENTS.md hierarchy, rules files, gates that actually run on Linux |

If `$ARGUMENTS` names an axis, grade every axis but go deep on that one.

## 2. Write the ADR

Take the subagent's table and record it as an ADR, using the `/adr`
numbering convention:

1. List `docs/adr/` and take the next free `NNNN`.
2. Write `docs/adr/NNNN-north-star-grade.md` from `docs/adr/template.md`.
3. `status: proposed`, today's date. Do **not** mark it `accepted` — that
   happens when a human merges it.
4. The body carries the rubric table verbatim:

   ```markdown
   | Axis | Standard | This repo | Verdict |
   |---|---|---|---|
   ```

   `Standard` is what lang-swift-apple asks for, in one line. `This repo` is
   what is actually here, with a path. `Verdict` is one of
   **MEETS** / **PARTIAL** / **DIVERGES** / **GAP**.
5. Under the table, three sections: **Deliberate divergences** (each with the
   ADR that authorises it, or a note that none exists), **Gaps worth
   closing** (ranked, with the smallest first), and **Not worth closing**
   (with the reason — "documented in template-guide §10" is a valid reason).
6. Append a row to `docs/adr/README.md`.

## 3. Report

Two things in chat, and nothing else: the ADR path, and the count by verdict
(`n MEETS / n PARTIAL / n DIVERGES / n GAP`). The table lives in the file;
do not paste it back into the conversation.
