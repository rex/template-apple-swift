# Questions — W2E (fun layer + specialists)

Filed at hand-off. Nothing here blocked implementation; everything is coded to
`contracts.md` + `gate-w1-resolutions.md` as written.

## Q1 — `onboard.md` ownership collision (needs a decision at integration)

`file-ownership.md` gives W2E only `.claude/commands/{release,grade-north-star}.md`
and gives W2D "all `.claude` except W2E's enumerated files". Resolution #15 says
"`/onboard` (W2E→W2D command)", which reads both ways. **My brief enumerates
`.claude/commands/onboard.md` as W2E deliverable #5 with a full spec** (frontmatter
incl. `AskUserQuestion`, Batches A–D, macOS-only `make bootstrap` note, ASC
handoff, one-shot warning).

W2D had already written a version (its own, shorter). I wrote the brief-spec'd
version **as a superset**: W2D's refuse-early `template/` guard, dry-run→apply
flow, `--dest` alternative and post-transform checklist all survive; what I added
is the AskUserQuestion batching, the "does an ASC record already exist?"
question, the macOS-only bootstrap statement with the `verify-macos.yml` pointer,
and the closing ASC handoff block.

**Action needed:** if W2D writes `onboard.md` again after this hand-off, the four
additions above must survive the merge. Nothing else of mine touches W2D's files.

## Q2 — spinner drift is EXPECTED right now (Fable, Phase 4)

Per resolution #14 I did **not** touch `.claude/settings.json`. It currently
carries W2D's placeholders (1 verb, 1 tip); the corpus is 194 verbs and 37 tips.
So `make spinner-check` **fails today**, by design:

```
spinner: settings.json has drifted from the corpus
  spinnerVerbs.verbs: 1 in settings.json, 194 in the corpus
```

Fix at integration, before `make verify` can go green:

```bash
make spinner-sync          # or: python3 scripts/sync_spinner_verbs.py
```

Two properties worth knowing before you run it:

- It rewrites the whole file with `json.dump(indent=2)`. Key order is preserved
  (`$schema`, `spinnerVerbs`, `spinnerTipsOverride`, `hooks`, `permissions`
  verified), but W2D's inline one-line arrays become multi-line. That is the
  authoritative format from then on.
- It is a no-op when already in sync — it does not rewrite the file just to
  reformat it, so it will not churn W2D's formatting on later runs.

## Q3 — `statusLine` wiring is W2D's half

I shipped `.claude/statusline.sh` (executable, shellcheck-clean, ~20 ms with jq /
~45 ms on the python3 fallback). The settings key that activates it is
`.claude/settings.json`-side and therefore W2D's. The exact fragment is in the
script header and in contracts §12 / R5 SD-5:

```json
"statusLine": { "type": "command",
                "command": "${CLAUDE_PROJECT_DIR}/.claude/statusline.sh",
                "padding": 1, "refreshInterval": 10 }
```

Default is `ops.statusline: false`, so the key should be **absent** from the
committed template settings and added only by the generator when answered true.

## Q4 — generator payload for the two `ops` flags (W2A / Fable)

These are `ops` flags, not components, so `template/components.yaml` does not
describe them. Confirm the generator handles both:

- `ops.spinner_flavor: false` → delete `.claude/spinner-verbs.txt`,
  `.claude/spinner-tips.txt`, `scripts/sync_spinner_verbs.py`, **and** the
  `spinnerVerbs` + `spinnerTipsOverride` keys from `settings.json`. (Leaving the
  keys with the script gone is harmless — `make spinner-sync/-check` guard on the
  script's existence and exit 0 — but leaving the corpus without the script means
  a stale settings.json nobody re-syncs.)
- `ops.statusline: false` → delete `.claude/statusline.sh` and do not add the
  `statusLine` key.
- `ops.spinner_flavor: true` → run the sync **after** token substitution
  (contracts §12), because the corpus contains a `MyApp` token on purpose.

## Q5 — one verb carries a `MyApp` token, deliberately

`.claude/spinner-verbs.txt` contains `Shipping MyApp` (15 chars) to exercise the
rename path that contracts §12 explicitly permits. Consequences:

- The two `.txt` files and `settings.json` must stay **off** the generator's
  binary skip-list, and the post-rename zero-residual-token lint applies to them
  normally.
- After rename the entry may exceed the ≤16-char display budget for a long app
  name (`Shipping Pennywise` = 18). That is cosmetic — Claude Code imposes no
  length cap (R5-V7) — and the corpus header says so. Drop the line if that
  bothers anyone.

## Q6 — corpus voice (FYI, no action)

The verb corpus is profane and heavily innuendo-laden per explicit instruction
(Pierce's request). No slurs, no hate, nothing sexual involving minors. It is a
plain-text list with one entry per line, so trimming it to taste is a one-line
edit followed by `make spinner-sync` — worth a sentence in whatever README
section covers the spinner.
