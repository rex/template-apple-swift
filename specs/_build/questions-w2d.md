# Questions — W2D (agentic layer)

Cross-partition items found while building `.claude/**`, `.mcp.json`,
`VIBE.yaml`, the root docs, `specs/_template/**`, `docs/template-guide.md`,
`.codex/`, `.gemini/` and the skeleton `scripts/*.py` copies. I coded to the
contract as written and did not touch anything outside my partition.

Ordered by how likely each is to break the Phase-4 gate.

---

## Q1 — `VERSION` is required by three partitions and owned by none (BLOCKER)

`file-ownership.md` assigns no owner to the root `VERSION` file, and it does
not exist in the tree. It is required by:

- `scripts/bump_version.py` and `scripts/check_version_bumped.py` (my copies —
  the version gate in `make lint` / `stop-gate.sh` cannot pass without it);
- `VIBE.yaml` `versioning.file: VERSION` (mine, per brief);
- W2B's handoff §2: `make bootstrap` must derive `MARKETING_VERSION` from
  `VERSION` + `git rev-list --count HEAD` into `Config/Versions.xcconfig`;
- contracts §7 (ADR-0007), which specifies it as plain semver.

I did **not** create it — it is outside my enumerated partition.

**Requested:** create `VERSION` containing `0.1.0` (matching my `CHANGELOG.md`
seed entry and `versioning.initial`), and assign it in `file-ownership.md`.
W2C is the natural owner since its Makefile reads it.

---

## Q2 — W2A's `vibe.py` looks for VIBE.yaml paths that the merged schema forbids

`template/tmpl/vibe.py` retunes VIBE.yaml by dotted path, with a candidate
list per logical field. Four of its candidate sets contain no path that exists
in a schema-valid VIBE.yaml. This is **not fatal** — an unmatched path is
recorded as a note ("key(s) not present, left alone") — but it means those four
values are silently never retuned at onboarding.

I wrote VIBE.yaml to the schema (`lang-swift-apple/vibe-schema-fragment.yaml` +
`tool-ci/vibe-schema-fragment.yaml`, both `additionalProperties: false`) and
confirmed it green:

```
uv run scripts/validate_vibe_yaml.py --skills-dir <skeleton> --skill-search-paths <skills>
→ ✓ VIBE.yaml passes schema validation
```

| Logical field | `vibe.py` candidates | Schema-valid path (what I wrote) |
|---|---|---|
| deployment floors | `apple.deployment_target.*`, `apple.deployment.*`, `apple.min_os.*` | `apple.deployment_targets.{ios,macos,watchos}` (**plural**) |
| CI system | `apple.ops.ci_system`, `ops.ci_system`, `apple.ci_system`, `ci.system` | `apple.distribution.ci_system` |
| signing | `apple.ops.signing`, `ops.signing`, `apple.signing` | `apple.code_signing` |
| autonomy | `ops.autonomy`, `autonomy.mode`, `project.autonomy` | `workflow.default_autonomy_mode` |

Note that `apple.ops.*` and a top-level `ops:` can never be valid: `apple` is
`additionalProperties: false` and so is the merged root.

**Requested:** W2A appends the right-hand column to each candidate list (four
one-line edits, no behavior change for existing candidates). Also worth
knowing: my brief said `ci: {... pin true}`, but the tool-ci schema spells it
`pin_actions_to_sha`, so that is what I wrote.

---

## Q3 — `make check-module-rules` fails on `template/tmpl/answers.py`

```
✗ template/tmpl/answers.py — 10 public entry points (2 over the cap of 8)
```

This is the only remaining failure in the gate chain and it is in W2A's
partition, so I did not touch it. Two clean options: split the module (e.g.
identity normalization vs. answers access), or `_`-prefix the helpers that are
not part of its public surface.

I resolved the same failure for two files I own but cannot edit —
`scripts/skill_checks.py` (15) and `scripts/validate_vibe_yaml.py` (10) are
vendored verbatim from agentic-skeleton, so I added them to
`architecture.exclude_globs` with a comment rather than forking the skeleton.
Please sanity-check that call. (I would rather not extend that exclusion to
first-party generator code.)

---

## Q4 — `sync_skeleton.py` deletes a hook that contracts §12 wires

`agentic-skeleton/scripts/sync_skeleton.py` lists
`.claude/hooks/pre-compact.sh` in its `RETIRED` tuple, so
`make sync-skeleton --apply` **deletes** it. Contracts §12 / R5 SD-2 wire a
`PreCompact` handler to exactly that path, and my self-check requires every
referenced hook to exist and be executable.

The skeleton retired it because PreCompact rejected
`hookSpecificOutput.additionalContext` with a schema error. I wrote a net-new
`pre-compact.sh` that emits only `systemMessage` + `suppressOutput` (universal
output fields, accepted on every event), so it cannot hit that failure — but
the RETIRED-list collision remains.

**Requested:** decide one of —
(a) drop `pre-compact.sh` from the skeleton's RETIRED list in the Phase-6
skill-update proposal (my preference — the file is legitimate again);
(b) rename ours to `pre-compact-apple.sh` and amend contracts §12.
Until then it is documented in `docs/template-guide.md` § Hazards and `MAP.md`.

---

## Q5 — `make sync-skeleton --apply` re-introduces the three Serena files

`VERBATIM_CLAUDE_DIRS` copies *every* `*.sh` from the skeleton's
`.claude/hooks/` and every `*.md` from `.claude/rules/`. That includes
`serena-required.sh`, `serena-gate.sh` and `rules/serena.md`, all of which
ADR-0005 removes ("No Serena server, hook, rule, flag, or workflow step exists
anywhere"). They would arrive **unwired and inert** — `settings.json` is
Advisory and never blind-copied, so nothing would execute them — but their
presence contradicts the ADR.

Related: three verbatim skeleton files I copied still *mention* Serena, and I
left every one of them byte-identical.

| File | What it contains | Fires here? |
|---|---|---|
| `hooks/session-start.sh` | a Serena orientation branch guarded by `grep -q '"serena"' .mcp.json` | no — our `.mcp.json` has no Serena entry |
| `commands/scaffold.md`, `commands/retrofit.md` | a Serena init sequence, explicitly conditional: *"Skip this step ONLY if `.mcp.json` does not declare `serena`"* | no — and these commands bootstrap OTHER repos, where Serena may legitimately be declared |
| `commands/sync-skills.md` | one conditional line about `serena-required.sh` | no |

I read R5 SD-7 as settling this: it enumerates the removal set as *"exactly
two `settings.json` entries … plus the two scripts and `rules/serena.md`"* —
the commands are not in it. Contracts §11 likewise bans a Serena "server,
hook, rule, flag, or workflow step", none of which a conditional paragraph in
a generic bootstrap command is. Editing them would trade dead conditional text
for permanent `sync-skeleton` drift on three files.

**Requested:** confirm byte-identity was the right trade on all four files,
and add the re-introduction problem to the Phase-6 skill-update proposal.

---

## Q6 — Skill provenance: `VERSION` file vs. `SKILL.md` frontmatter

My brief specified `lang-swift-apple 0.3.0` and `agentic-skeleton 0.2.0`.
Those are the `version:` fields in each skill's **SKILL.md frontmatter**, which
are stale relative to the skills' **VERSION files** — and the VERSION file is
what `stamp_skill.py` writes and `check_skills.py` compares against.

| Skill | SKILL.md `version:` | `VERSION` file |
|---|---|---|
| agentic-skeleton | 0.2.0 | **0.44.0** |
| lang-swift-apple | 0.3.0 | **0.4.0** |
| tool-ci | 0.1.0 | **0.7.1** |

I wrote the VERSION-file values, so `make check-skills` reports
"provenance current" instead of a 42-minor-version phantom drift. I also added
a **fourth** entry, `tool-ci`, because `check_skills.py` flags a namespace
present in VIBE.yaml with no matching `skills:` entry — and the brief required
the `ci:` block. Both divergences are commented in VIBE.yaml.

**Requested:** confirm. If the brief's numbers were deliberate, say so and I
will revert. Separately, the three skills' stale frontmatter is worth a line in
the Phase-6 skill-update proposal.

---

## Q7 — I created `.claude/commands/onboard.md`; confirm it is mine

My brief lists only "verbatim skeleton 10" for `.claude/commands/`, but
resolution #15 names `/onboard` as a "W2E→W2D command", `file-ownership.md`
gives W2D all of `.claude/**` except W2E's two enumerated commands, and my
README + AGENTS.md banner + `session-start-apple.sh` all point at `/onboard`
as the template's headline flow. A dead link there would be the single most
visible defect in the repo, so I wrote it.

It invokes exactly the frozen CLI (`uv run template/generate.py --answers
<file> [--dest DIR | --apply] [--dry-run]`), sets
`disable-model-invocation: true` per contracts §12, and refuses early when
`template/` is absent.

**Requested:** confirm ownership. If W2E was writing one too, mine should lose.

---

## Q8 — `.gitignore` does not cover `.claude/settings.local.json` (minor)

W1A owns `.gitignore`. `template/answers.local.yaml` is correctly ignored.
Claude Code writes `.claude/settings.local.json` for per-user overrides
(`/skills` writes `skillOverrides` there, among other things), and it should
not be committed.

**Requested:** append `.claude/settings.local.json` to `.gitignore`.

---

## Notes (no action needed)

- **Spinner placeholders.** Per resolution #14 I wrote placeholder
  `spinnerVerbs` / `spinnerTipsOverride` blocks and did not touch W2E's
  corpora. The brief's literal `tips: ["placeholder"]` would ship a visible
  dummy string if the Phase-4 sync were ever skipped, so I used one real tip
  quoted verbatim from R5 SD-2 instead. One verb (`Xcodegenerating`), one tip.
  `scripts/sync_spinner_verbs.py` overwrites both arrays wholesale.
- **Agent/command frontmatter fixes.** Per contracts §12 / R5 SD-4, I diverged
  from byte-identity on exactly 10 skeleton files: `tools:` in 4 agents
  (permission-rule syntax there silently strips the tool — R5-V26), and
  `Task` → `Agent` + a stale `MultiEdit` in 6 commands. Every other skeleton
  copy is byte-identical, verified with `cmp`. SD-6 already routes the upstream
  fix into the Phase-6 skill-update proposal.
- **No `statusLine` key** in `settings.json` (opt-in via `ops.statusline`,
  materialized by W2A's `settingsjson.py`), and **no `permissions.allow`** —
  allow arrays merge across scopes, so adding one would *grant* rather than
  narrow.
- `scripts/mcp/op-headers.sh` was smoke-tested here against all its branches;
  path A returns a valid `{"Authorization": ...}` object and the degradation
  paths return `{}` with a stderr reason, exit 0.
