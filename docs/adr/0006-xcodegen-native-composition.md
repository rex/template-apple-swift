# ADR 0006 — Tool-capability maximization; xcodegen-native project composition

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner), Fable
- **Scope:** Standing engineering principle + the project.yml/generator design
  it immediately reshaped

## Context

Pierce's directive: use every native capability of every tool on hand instead
of hand-rolling or working around it, wherever possible and reasonable. The
first plan draft hand-rolled a marker-splicing engine over a monolithic
project.yml — while xcodegen natively supports `include:` composition with
deep-merge, xcconfig `configFiles`, `targetTemplates`, `settingGroups`, and
`bundleIdPrefix`. Pennywise separately proves the cost of ignoring native
features: its CI patches project.yml with indentation-sensitive awk because
versions live as YAML literals.

## Decision

1. **Standing principle** (applies to every tool in the repo: xcodegen,
   fastlane, uv, pytest, GitHub Actions, xcodebuild, Claude Code surfaces):
   prefer the tool's native capability; hand-rolling what a tool already does
   is a defect. Every research brief carries a capability-audit sub-task.
2. **project.yml composition:** root `project.yml` (options, settingGroups,
   targetTemplates, configFiles, always-on targets, schemes) + one
   `xcodegen/components/<id>.yml` per prunable component carrying its targets
   AND its merge fragments (host `dependencies:` edge, scheme additions,
   capability source entries). **Prune = delete the component file + its
   `include:` line.** Research R2 verifies deep-merge semantics for list-valued
   keys; the narrow contingency is `# @component:<id>`-tagged lines in the root
   file removed by line, never a splice engine.
3. **Versions in xcconfig:** `Config/Versions.xcconfig` carries
   `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`; CI and release lanes write
   that 2-line file. project.yml is never patched by automation.
4. Swift-source component seams still use `// @template:<id> BEGIN/END`
   markers (≤8 enumerated files) — source-level composition is inherently the
   generator's job, not xcodegen's.

## Consequences

- The generator shrinks to: delete files, drop include lines, strip marker
  blocks, edit plists via plistlib, substitute tokens — no YAML surgery.
- The committed superset (all includes present) is exactly what verify-macos
  builds; combos differ only by deleted files.
- If R2 finds include merging insufficient for dependency edges, only the
  tagged-line contingency activates; the ADR stands.
