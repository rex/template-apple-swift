# Questions — W2A (the generator)

Filed at the end of Wave 2. Nothing here blocks W2A: every item below is coded
defensively against the contract as written, degrades to a printed `note:`
rather than a failure when a sibling's file is absent or shaped differently,
and is covered by a unit test that pins the behaviour either way. Fable should
resolve them at Phase-4 integration, when all partitions exist on disk.

---

## Q1 — W2D: exact key spellings in `VIBE.yaml`

`template/tmpl/vibe.py` edits VIBE.yaml through line surgery (a `yaml.safe_load`
→ `yaml.dump` round-trip is forbidden — the comments are the policy
documentation). Line surgery needs the literal dotted key paths. The
component-driven half is derived from `components.yaml`'s `vibe:` maps and is
therefore self-maintaining:

| From the registry | Path written |
|---|---|
| `platforms+` | `apple.platforms` (list; base `[iOS]`) |
| `universal_purchase` | `apple.universal_purchase` |
| `extensions.*` | `apple.extensions.widget_kit` / `.live_activity` / `.notification_service` / `.watch_complications` |
| `persistence` | `apple.persistence` (`swiftdata` \| `none`) |
| `monetization` | `apple.monetization` (`iap` \| `none`) |
| `authentication` | `apple.authentication` (list; `[]` when off) |

The rest is guessed from a candidate list; the FIRST path that exists in the
file wins, and any field whose candidates are all absent is reported as
`VIBE.yaml: N key(s) not present, left alone: …` and left untouched — the
generator never appends keys to someone else's policy file.

| Logical field | Candidates tried, in order |
|---|---|
| project name | `project.name` |
| display name | `project.display_name`, `project.display`, `apple.display_name` |
| iOS floor | `apple.deployment_target.ios`, `apple.deployment.ios`, `apple.min_os.ios` |
| macOS floor | same three with `.macos` |
| watchOS floor | same three with `.watchos` |
| CI system | `apple.ops.ci_system`, `ops.ci_system`, `apple.ci_system`, `ci.system` |
| signing | `apple.ops.signing`, `ops.signing`, `apple.signing` |
| autonomy | `ops.autonomy`, `autonomy.mode`, `project.autonomy` |

**Ask:** confirm the real spellings, or tell me which to keep and I will drop
the alternates. Note that `identity.bundle_root` / `team_id` inside VIBE.yaml
need no entry here — they are plain text and the rename engine already
substitutes them.

Also for W2D: resolution #13 requires
`architecture.exclude_globs: UITests/MyAppUITests/SnapshotHelper.swift`.
`verify.py` currently emits it as the one standing soft-cap warning
(315 > 250) in every mode; that warning disappears the moment the glob lands.

---

## Q2 — W2C: `verify-macos.yml` matrix key name

`workflows.collapse_matrix()` looks for a whole-line matrix key named `combo:`,
`config:` or `configuration:` (flow list `[a, b]` or block list, either style)
and rewrites its value to a single entry — the generated app's slug. If no such
key exists the file is left untouched with a `note:`.

**Ask:** confirm the key name, and confirm the intended single value. I use
`ident.slug` (e.g. `probe`); if the matrix entries are combo names from
`template/ci-combos/*.yaml`, a generated repo has no combo name, so the slug is
the only meaningful stand-in. Say the word and I will emit something else.

---

## Q3 — W2C: `ci.yml` template-only job markers

I strip every line between whole-line `# >>> template-ci` and
`# <<< template-ci` (markers included), as frozen. That is a verbatim line
range, so each marked region must be a complete, self-contained set of job
blocks at job indentation — a marker opening mid-block would leave invalid
YAML. Unit-tested both ways in `template/tests/test_workflows.py`.

**Ask:** confirm the markers wrap whole jobs (not steps inside a shared job).

---

## Q4 — W2C: make targets named in generated docs

Generated `AGENTS.md` / `README.md` / `PROGRESS.md` tell the reader to run:
`make bootstrap`, `make regenerate`, `make build`, `make test`, `make lint`,
and — only when the matching component is enabled — `make build-mac`,
`make build-watch`. The `signing: match` path additionally names `make certs`.

**Ask:** confirm those exist with those names (contracts §8 fixes the fastlane
delegates; these are the build-side ones). Any rename is a one-line edit in
`template/docs/fragments/agents/{10-always,11-mac,12-watch}.md`.

---

## Q5 — W2E/W2D: the spinner sync contract

When `ops.spinner_flavor: true`, the generator runs
`scripts/sync_spinner_verbs.py` with **no arguments** (sync mode), through
`sys.executable` with `cwd` = the generated repo, and treats a non-zero exit as
fatal. When false it deletes `.claude/spinner-verbs.txt`,
`.claude/spinner-tips.txt` and the script, and removes the `spinnerVerbs` /
`spinnerTipsOverride` keys from `.claude/settings.json`.

**Ask:** confirm (a) bare invocation means "sync", (b) the script needs nothing
beyond stdlib + pyyaml, (c) it is safe to run against a settings.json whose
spinner blocks are still W2D's placeholders. If the script must be invoked as
`--sync` or similar, that is one constant in `tmpl/settingsjson.py`.

Related: `ops.statusline` false deletes `.claude/statusline.sh` and drops the
`statusLine` key; true writes contracts §12's object verbatim. settings.json is
edited via `json.load`/`json.dump(indent=2)` — safe because it is strict JSON
with no load-bearing comments, unlike VIBE.yaml.

---

## Q6 — Fable: `specs/_build/` in a generated repo

`contracts.md` says `specs/_build/` is deleted before the template is tagged, so
the generator deliberately does not touch it. While it still exists, a residual
grep for the bare string `com.example` inside a generated tree hits six lines of
**prose** in `specs/_build/research/R2-*.md` and `contracts.md` (all of them
quoting the banned `bundleIdPrefix: com.example` example). They are not identity
tokens — `com.example.myapp` is, and it substitutes correctly — so
`rename.residual_tokens()` and `verify.py` are both clean. `MyApp` and `myapp`
are zero-hit in a renamed tree.

**Ask:** confirm `specs/_build/` is removed pre-tag. If it is ever meant to ship,
say so and I will add it to the prune list.

---

## Q7 — note only: `docs/` writes at generation time

The generator creates `docs/onboarding-record.md` and
`docs/onboarding-answers.yaml` **in the generated repo**, not in the template.
No collision with W2B's `docs/release-automation.md` / `docs/asc-setup.md` or
W2D's `docs/template-guide.md`, but flagging it so nobody claims those two
names later.

---

## Q8 — note only: `template/.gitignore` and `template/pytest.ini`

Both are new, both inside W2A's partition. They exist so the generator's own
pytest run cannot leave `__pycache__/` or `.pytest_cache/` where
`git ls-files --others --exclude-standard` — the copy oracle — would find them.
The root `.gitignore` (W1A's file) is untouched.
