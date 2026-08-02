# R5 — Claude Code customization surfaces (decisions 8–9)

Research date: **2026-08-02**. Claude Code latest at time of research: **v2.1.220**
(CHANGELOG head). All claims verified against `code.claude.com/docs` raw markdown
(`.md` suffix on each doc URL) and the published JSON Schema
(`schemastore.org/claude-code-settings.json`, 143 top-level properties) — not memory.

Scope: ADR-0008 (sync boundary: Apple additions are net-new files, `settings.json` is
Advisory and carries local wiring) and ADR-0005 (zero Serena). Deployed baseline read:
`/home/user/pennywise-apple-universal/.claude/settings.json`.

---

## Verdicts

### A. Spinner messages (Pierce's headline ask)

**V1. The mechanism exists and is named `spinnerVerbs`. It is a first-class,
documented, schema-validated settings key — not a hack.**
Evidence: `settings.md` line 324: `` `spinnerVerbs` | Customize the action verbs shown
while a turn is in progress. Set `mode` to `"replace"` to use only your verbs, or
`"append"` to add them to the defaults `` with the example
`{"mode": "append", "verbs": ["Pondering", "Crafting"]}`. Schema
(`claude-code-settings.json`) defines it as `type: object`, `additionalProperties:
false`, `required: ["verbs"]`, `mode` an enum of exactly `append` | `replace`, `verbs`
an `array` of `string` with `minLength: 1` per item and `minItems: 1`.
Added in **v2.1.23** (CHANGELOG: "Added customizable spinner verbs setting
(`spinnerVerbs`)").
Confidence: **high**.

**V2. `mode` is optional in the schema but must be set explicitly — do not rely on the
default.** `required` is `["verbs"]` only, so `mode` may be omitted; the docs never
state the omitted-`mode` behavior. Set `"mode": "append"` explicitly.
Confidence: **high** (schema is unambiguous that `mode` is optional; the *default* is
undocumented, which is precisely why we pin it).

**V3. There is a SECOND, distinct spinner surface: `spinnerTipsOverride` (plus the
on/off switch `spinnerTipsEnabled`). Verbs ≠ tips.** Verbs are the single gerund next
to the spinner ("Pondering…"); tips are the longer coaching sentences shown beside it.
Schema: `spinnerTipsOverride` is `type: object`, `required: ["tips"]`, with
`tips: array<string>` (`minItems: 1`) and `excludeDefault: boolean` (default `false`).
`settings.md` line 323: "`tips`: array of tip strings. `excludeDefault`: if `true`,
only show custom tips; if `false` or absent, custom tips are merged with built-in
tips". `spinnerTipsEnabled` (line 322) is `boolean`, **default `true`**; setting it
`false` disables tips entirely. Added in **v2.1.45**.
Confidence: **high**. → We should use **both**: verbs for flavor, tips for Apple-specific
coaching. Note the asymmetry: verbs use `mode: append|replace`; tips use
`excludeDefault: true|false`. Easy to get backwards.

**V4. Project-level `.claude/settings.json` DOES work for `spinnerVerbs`. No fallback
to a user-settings snippet is required.** Two independent proofs:
(a) `spinnerVerbs` and `spinnerTipsOverride` are **absent** from the exhaustive
user-settings-only list. That list is exactly: `autoMode`, `askUserQuestionTimeout`,
`enableArtifact`, `processWrapper`, `sshConfigs`, `pluginConfigs`, and
`footerLinksRegexes` — each of which carries explicit prose such as "Read from user
settings, the `--settings` flag, and managed settings only. Ignored in project
`.claude/settings.json` and local `.claude/settings.local.json`". The spinner rows carry
no such qualifier.
(b) `settings.md` line 60 uses a spinner key as its *canonical worked example of project
overriding user*: "if your user settings set `spinnerTipsEnabled` to `true` and project
settings set it to `false`, the project value applies."
Confidence: **high**. This kills the fallback branch of the brief entirely.

**V5. Project-level spinner settings survive into remote/web (cloud) sessions.**
`cloud-environments.md` "What carries over from your setup" table: "Your repo's
`.claude/settings.json` hooks — **Yes** — Part of the clone", alongside `.claude/rules/`,
`.claude/skills/`, `.claude/agents/`, `.claude/commands/`, `.mcp.json`. And
`claude-code-on-the-web.md`: "To change settings for a cloud session, use environment
variables or **commit settings files to the repository**." Conversely `~/.claude/...` is
explicitly **No** ("Lives on your machine, not in the repo").
Confidence: **high** for the settings *loading*. Whether the browser UI *renders* the
verb string the same way the TUI does is **not documented anywhere** — treat visual
parity in the web client as **low** confidence and unverified. Loading is what we
control; rendering is Anthropic's.

**V6. Merge semantics across scopes: `spinnerVerbs` is object-valued, and the documented
rule is that scalars override while *arrays* concatenate+dedupe. Whether the nested
`verbs` array participates in array-merge is genuinely ambiguous in the docs.**
`settings.md` "Settings precedence" Note: "**Array settings merge across scopes.** When
the same array-valued setting (such as `sandbox.filesystem.allowWrite` or
`permissions.allow`) appears in multiple scopes, the arrays are concatenated and
deduplicated, not replaced." But the "Key points" bullet says "Settings merge across
scopes; scalar values from higher-priority scopes override, and arrays concatenate" —
which reads as a deep merge that would reach `spinnerVerbs.verbs`. The two named
exceptions (`fallbackModel`, `availableModels`) are both top-level arrays, so they
don't settle it.
Confidence: **medium** on the exact mechanic — **but the design is made immune to it**:
with `"mode": "append"` the built-ins survive under either reading, and the only
difference is whether Pierce's personal verbs also survive inside our repos. Do **not**
ship `"mode": "replace"` at project level; under override semantics it would silently
erase both the built-ins *and* Pierce's personal corpus for every generated repo.

**V7. No count or length cap on `verbs` exists in the schema or the docs.** Schema
constrains only `minItems: 1` and per-item `minLength: 1`; no `maxItems`, no `maxLength`.
A 120+ entry corpus is well within spec. Practical constraint is display width, not a
limit. Confidence: **high** (absence verified programmatically against the schema).

**V8. Verbs must be present-participle/gerund forms, and custom verbs no longer leak
into the past-tense completion message.** Doc example values are `Pondering`, `Crafting`;
the built-in surface renders `<Verb>…`. Two CHANGELOG fixes bound this: **v2.1.141**
"Fixed `spinnerVerbs` setting not being honored in turn-completion messages" and
**v2.1.144** "Fixed custom `spinnerVerbs` applying to the post-turn duration message —
past-tense built-ins like 'Worked for 5s' are restored there". So on ≥ v2.1.144 the
corpus needs gerunds only; no past-tense variants required.
Confidence: **high**.

**V9. There is NO file-reference mechanism. `verbs` is an inline JSON array or nothing.**
The schema types `verbs` as `array` of `string`; no `$ref`, `file`, `path`, or `include`
form exists anywhere in the 143-property schema. Consequence for W2D/W2E: a curated
corpus file cannot be *read* by Claude Code — it must be **materialized into
`.claude/settings.json`** by our own tooling. See Spec delta SD-3.
Confidence: **high**.

**V10. Hot-reload: spinner settings apply without restart.** `settings.md` "When edits
take effect" plus the `ConfigChange` hook that "Fires when settings reload"; the
restart-required list is `model` and `outputStyle`. Community reports (Miessler,
Tristan Dunn, 28 Jan 2026) independently confirm instant effect.
Confidence: **high**.

**V11. Recommendation — one mechanism, both surfaces, project scope.** Ship
`spinnerVerbs` (`mode: append`) **and** `spinnerTipsOverride` (`excludeDefault: false`)
in the committed `.claude/settings.json`. Do not ship `spinnerTipsEnabled` (leave the
`true` default alone). No user-settings snippet, no onboarding print step, no statusline
substitute is needed for the headline ask. Confidence: **high**.

### B. statusLine

**V12. Current schema is `{type, command, padding?, refreshInterval?,
hideVimModeIndicator?}`, and it works at project scope.** From the JSON Schema:
`type` is `const: "command"` (required), `command` is a required `string`,
`padding` is `number` (default `0`), `refreshInterval` is `integer` with `minimum: 1`,
`hideVimModeIndicator` is `boolean`; `additionalProperties: false`.
`statusline.md`: "Add a `statusLine` field to your user settings … **or project
settings**." `refreshInterval` re-runs the command every N seconds *in addition to*
event-driven updates — needed when "background subagents change git state while the main
session is idle." Confidence: **high**.

**V13. stdin JSON is far richer than the commonly-cited fields.** Full documented
payload: `cwd`, `session_id`, `session_name`, `prompt_id`, `transcript_path`,
`model.{id,display_name}`,
`workspace.{current_dir,project_dir,added_dirs,git_worktree,repo.{host,owner,name}}`,
`version`, `output_style.name`,
`cost.{total_cost_usd,total_duration_ms,total_api_duration_ms,total_lines_added,total_lines_removed}`,
`context_window.{total_input_tokens,total_output_tokens,context_window_size,used_percentage,remaining_percentage,current_usage.{input_tokens,output_tokens,cache_creation_input_tokens,cache_read_input_tokens}}`,
`exceeds_200k_tokens`, `fast_mode`, `effort.level`, `thinking.enabled`,
`rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`, `vim.mode`,
`agent.name`, `pr.{number,url,review_state}`,
`worktree.{name,path,branch,original_cwd,original_branch}`.
Conditionally absent: `session_name`, `workspace.git_worktree`, `workspace.repo`,
`effort`, `prompt_id`. `context_window.*` are current-window counts as of v2.1.132 (were
cumulative before). Confidence: **high**.

**V14. Cadence: event-driven with a 300 ms debounce; in-flight runs are cancelled.**
`statusline.md`: "Claude Code debounces updates at 300ms… If a new update triggers while
your script is still running, Claude Code cancels the in-flight script." Our script must
therefore be *fast* — no `xcodebuild`, no network, no `xcodegen`. `git` calls only, and
ideally `git rev-parse`-class ones. Confidence: **high**.

**V15. ANSI colors, OSC 8 hyperlinks, emoji, and multi-line output are all supported.**
"Multiple lines: each `echo` or `print` statement displays as a separate row."
"Colors: use ANSI escape codes like `\033[32m`". "Links: use OSC 8 escape sequences."
Terminal width is **not** readable via `tput cols` — Claude Code sets `COLUMNS` and
`LINES` env vars instead (v2.1.153+). The status line "runs locally and does not consume
API tokens." Confidence: **high**.

**V16. Caveat that governs our recommendation: `statusLine` is object-valued and does
NOT merge — a project statusLine wholesale shadows Pierce's personal one, and
`disableAllHooks` kills it too.** `settings.md` line 256: "`disableAllHooks` | Disable
all hooks **and any custom status line**." Confidence: **high** for the
`disableAllHooks` coupling; **medium-high** for non-merge (object-valued settings are
not in the array-merge carve-out).
→ Recommendation: ship the script as a net-new repo file but gate the *wiring* behind an
answers-file toggle defaulting to `false`, so we never silently stomp a personal
statusline. See SD-5.

**V17. `subagentStatusLine` is a separate, newer key we are not using.** Schema:
`{type: const "command", command: string}` — no `padding`/`refreshInterval`. Renders the
per-subagent row body in the agent panel. v2.1.214 added reasoning effort to its payload.
Confidence: **high**. Noted in the capability audit, not proposed for v1.

### C. Project-level `.claude/skills/`

**V18. Repo-local skills are fully supported, load for all collaborators, and are the
recommended successor to `.claude/commands/`.** `skills.md` "Where skills live" table:
Project = `.claude/skills/<skill-name>/SKILL.md`, "This project only". Precedence:
enterprise > personal > project; plugin skills are namespaced `plugin-name:skill-name`
and cannot conflict. "Files in `.claude/commands/` still work and support the same
frontmatter. **Skills are recommended** since they support additional features like
supporting files." If a skill and a command share a name, **the skill wins**.
Confidence: **high**.

**V19. The slash-commands doc has been folded into the skills doc.**
`code.claude.com/docs/en/slash-commands.md` now serves the *identical* body as
`skills.md` (byte-identical, 73,907 bytes, both titled "Extend Claude with skills").
Slash commands are no longer a separate concept in the documentation.
Confidence: **high** (verified by byte-for-byte fetch of both URLs).

**V20. Skill frontmatter is now large: `name`, `description`, `when_to_use`,
`argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`,
`allowed-tools`, `disallowed-tools`, `model`, `effort`, `context`, `agent`,
`background`, `hooks`, `paths`, `shell`. All optional; only `description` is
recommended.** Notable for us:
- `paths` — glob patterns that gate automatic activation (e.g. `"**/*.swift"`).
- `context: fork` + `agent:` — runs the skill in a forked subagent; **as of v2.1.218
  this defaults to background**, opt out with `background: false`.
- `disable-model-invocation: true` — user-only invocation, for side-effectful workflows.
- `model` accepts `inherit`; `effort` accepts `low|medium|high|xhigh|max`.
- Booleans accept `yes/no/on/off/1/0` case-insensitively as of v2.1.218.
Confidence: **high**.

**V21. Command name comes from the DIRECTORY name, not frontmatter `name` — except in
plugins.** "In a personal or project skill, `name` sets only the display label shown in
skill listings, and the command still comes from the directory or file name."
`.claude/skills/deploy-staging/SKILL.md` → `/deploy-staging`. Confidence: **high**.
This is a trap: naming the directory and the `name:` field differently silently produces
a mismatch between what `/`-autocomplete shows and what the listing shows.

**V22. Project skills carry a workspace-trust gate on their privileged fields.**
"For skills checked into a project's `.claude/skills/` directory, `allowed-tools` takes
effect after you accept the workspace trust dialog for that folder… Review project skills
before trusting a repository, since a skill can grant itself broad tool access."
Confidence: **high**. Relevant because our generated repos are cloned by Pierce and by CI.

**V23. Skill/plugin interplay: adding `.claude-plugin/plugin.json` to a skill folder
promotes it to a plugin (`<name>@skills-dir`) that can bundle agents, hooks, and MCP
servers — but in a project's `.claude/skills/` this requires accepting workspace trust
first.** Live change detection covers `SKILL.md` text only; `hooks/`, `.mcp.json`,
`agents/`, `output-styles/` inside a skills-dir plugin need `/reload-plugins`.
Confidence: **high**.

**V24. Cloud/Cowork asymmetry worth documenting in the template's README.** Cloud
sessions load project `.claude/skills/` from the clone; Cowork sessions do **not** read
`~/.claude/skills/` and load claude.ai-account-enabled skills instead. A personal-only
skill is "not found" when a routine invokes it. Confidence: **high**.

### D. Subagents

**V25. Current frontmatter field set (only `name` + `description` required):**
`name`, `description`, `tools`, `disallowedTools`, `model`, `permissionMode`,
`maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `effort`,
`isolation`, `color`, `initialPrompt`. Confidence: **high**.
- `model`: `sonnet` | `opus` | `haiku` | **`fable`** | full ID (e.g. `claude-opus-5`,
  `claude-sonnet-5`) | `inherit`. **Default is `inherit`.**
- `permissionMode`: `default` | `acceptEdits` | `auto` | `dontAsk` | `bypassPermissions`
  | `plan` | `manual` (alias for `default`, v2.1.200+).
- `memory`: `user` | `project` | `local`.
- `isolation`: `worktree` — runs the subagent in a temp git worktree branched from the
  **default branch**, auto-cleaned if no changes.
- `color`: `red|blue|green|yellow|purple|orange|pink|cyan`.
- `effort`: `low|medium|high|xhigh|max`.
- `background`: default is unset → Claude chooses, and **as of v2.1.198 it runs subagents
  in the background by default**.
- `name` **must not contain `:`** (v2.1.218+ rejects the file and logs an error);
  `:` is reserved for plugin scoping.

**V26. DEFECT IN THE DEPLOYED BASELINE: `tools:` takes tool NAMES, not permission rules.
Pennywise's agents put permission-rule syntax there and are silently losing Bash.**
`sub-agents.md`: "`tools` | Tools the subagent can use… If no entry in the list resolves
to a tool, the subagent usually fails to launch." The worked examples are bare names
(`tools: Read, Grep, Glob, Bash`). The only non-bare forms accepted are
`Agent(type,…)` and MCP patterns `mcp__<server>` / `mcp__<server>__*`.
`/home/user/pennywise-apple-universal/.claude/agents/reviewer.md` line 4 reads:
`tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git status:*)`
— `Read`, `Grep`, `Glob` resolve, so the agent launches, but none of the three `Bash(...)`
entries resolve to the `Bash` tool. **The reviewer subagent has no shell at all.** Same
pattern is present across the skeleton's agent set. This is a live bug in the skeleton,
not just in Pennywise. Confidence: **high**.
Fix: `tools: Read, Grep, Glob, Bash` and express the git-only narrowing via
`permissions.allow` in `settings.json` or per-hook `if:` filters.

**V27. Custom subagents are auto-discovered and auto-delegatable — no registration.**
Claude Code watches `~/.claude/agents/` and `.claude/agents/` and picks up edits "within
a few seconds… with no restart needed" (restart needed only when creating a scope's
*first* agent file in a new directory). Discovery walks up from cwd to repo root and
scans recursively into subfolders; identity comes only from the `name` field. Explicit
invocation: natural language, `@agent-<name>`, or session-wide `--agent <name>` /
`"agent": "<name>"` in settings. Cloud sessions: "Subagents defined in your repo's
`.claude/agents/` are picked up automatically." Confidence: **high**.

**V28. `Task` was renamed `Agent` in v2.1.63; `Task(...)` still works as an alias.**
Pennywise's `.claude/commands/review.md` lists `Task` in `allowed-tools` — functional,
but our template should emit `Agent`. Confidence: **high**.

**V29. Nesting and fan-out are now capped by default and the caps moved recently.**
v2.1.217 stopped nested spawning by default; **v2.1.219 re-enabled nesting to depth 3**
(`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` to disable). Concurrency cap default 20
(`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`); per-session spawn cap default 200
(`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`), reset by `/clear`. Confidence: **high**.
Relevant only if the template ever documents parallel-agent workflows.

**V30. Plugin subagents silently ignore `hooks`, `mcpServers`, and `permissionMode`.**
"For security reasons, plugin subagents don't support the `hooks`, `mcpServers`, or
`permissionMode` frontmatter fields." Direct argument against plugin-packaging our
agents. Confidence: **high**.

### E. Slash commands

**V31. `.claude/commands/*.md` still works, uses the same frontmatter as skills, and is
superseded-but-not-deprecated.** `description`, `argument-hint`, `allowed-tools`, and
`model` from Pennywise's files are all still valid — they are now documented as the
skills frontmatter set. `allowed-tools` here **does** take permission-rule syntax
(unlike subagent `tools:`), so `Bash(git diff:*)` in `.claude/commands/review.md` is
correct. Confidence: **high**.

**V32. Argument passing is substantially richer than `$ARGUMENTS`.**
`$ARGUMENTS` (all args; if absent from the body, args are appended as
`ARGUMENTS: <value>`), `$ARGUMENTS[N]` and its `$N` shorthand (0-based),
`$name` via an `arguments:` frontmatter list, plus `${CLAUDE_SESSION_ID}`,
`${CLAUDE_EFFORT}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`. Indexed args use
shell-style quoting. Escape a literal with a backslash: `\$1.00`. An unmatched `$2`
stays literal; an unmatched *named* arg expands to empty string.
Confidence: **high**.

**V33. Bash-context injection is ALIVE and unchanged: `` !`<command>` ``.**
`skills.md` "Inject dynamic context": "The `` !`<command>` `` syntax runs shell commands
before the skill content is sent to Claude. The command output replaces the placeholder."
There is also a ` ```! ` fenced block form (referenced by the `shell` frontmatter field).
Pennywise's `- Branch: !`git branch --show-current`` is current-correct.
The `shell:` frontmatter field selects `bash` (default) or `powershell` for these.
Confidence: **high**.

**V34. `${CLAUDE_SKILL_DIR}` is substituted in BOTH the body and `allowed-tools` Bash
rules (v2.1.129+), which lets a skill run its own bundled script with zero prompts.**
`allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)`.
`${CLAUDE_PROJECT_DIR}` substitution requires v2.1.196+. Confidence: **high**.

### F. Hooks

**V35. The event list has grown from Pennywise's 5 to ~30. Full current set:**
`SessionStart`, `Setup`, `InstructionsLoaded`, `UserPromptSubmit`,
`UserPromptExpansion`, `MessageDisplay`, `PreToolUse`, `PermissionRequest`,
`PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `PermissionDenied`,
`Notification`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`,
`Stop`, `StopFailure`, `TeammateIdle`, `ConfigChange`, `CwdChanged`, `DirectoryAdded`
(new in v2.1.219), `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`,
`PostCompact`, `SessionEnd`, `Elicitation`, `ElicitationResult`.
The brief's guesses are all real: `Notification`, `SubagentStop`, and `SessionEnd` all
exist. Confidence: **high**.

**V36. Handler types are now five, not one: `command`, `http`, `mcp_tool`, `prompt`,
`agent`.** `prompt` sends a single-turn model evaluation; `agent` spawns a tool-using
subagent to decide (marked experimental). Confidence: **high**.

**V37. Per-hook `timeout` is a documented field with event-specific defaults.**
Defaults: **600 s** for `command`/`http`/`mcp_tool`; **30 s** for `prompt`; **60 s** for
`agent`. `UserPromptSubmit` lowers the command/http/mcp default to **30 s**;
`MessageDisplay` to **10 s**; `SessionEnd` hooks share a **1.5 s** budget (raised to
match a longer explicit `timeout`, capped at 60 s). Confidence: **high**.
This directly bounds our `session-start-apple.sh` design.

**V38. Async support is real and has two flavors.** `async: true` (command hooks only)
runs in background, cannot block or return decisions, and delivers `additionalContext`
on the next conversation turn. `asyncRewake: true` implies `async` and **wakes Claude on
exit code 2**, surfacing stderr (or stdout if stderr is empty) as a system reminder —
this is the mechanism for a long `xcodebuild` reporting a failure back into an idle
session. Async completion notices are suppressed unless `--verbose`/Ctrl+O.
Confidence: **high**.

**V39. Two other handler fields matter for us: `if` and `statusMessage`.**
`if` takes exactly one permission rule (`"Edit(*.swift)"`, `"Bash(git *)"`) and is
evaluated **only on tool events** — on any other event a hook with `if` set *never runs*.
Single-segment dir patterns changed in v2.1.214: `"Edit(src/**)"` now matches only
`<cwd>/src`; use `"Edit(**/src/**)"` for any depth. `statusMessage` sets a **custom
spinner message displayed while the hook runs** — a third spinner surface, per-hook.
Confidence: **high**.

**V40. Exec form (`args`) removes the quoting hack in the deployed baseline.**
"A command hook runs as exec form when `args` is set… **Set `args` whenever the hook
references a path placeholder**, since each element is passed as one argument with no
quoting." Pennywise's `"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start.sh"` is
shell-form defensive quoting that exec form makes unnecessary. Both forms export
`CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA` to the child.
Confidence: **high**.

**V41. Hooks merge across settings levels rather than replacing.** "Hook entries merge
across settings levels rather than replacing each other: user, project, and local
settings add their own hooks without removing managed ones." This is what makes
ADR-0008's "second SessionStart entry / second PostToolUse entry" plan sound — but note
the merge is across *scopes*; within one file, our two entries are simply two matcher
groups in the same array. All matching hooks **run in parallel**, and identical handlers
are deduplicated (command hooks by command string + `args`). Confidence: **high**.

**V42. JSON I/O contract, current shape.** Common input adds `prompt_id` (v2.1.196+),
`permission_mode`, `effort.level`, `agent_id`, `agent_type` to the familiar
`session_id`/`transcript_path`/`cwd`/`hook_event_name`. Universal output fields:
`continue`, `stopReason`, `suppressOutput`, `systemMessage`, **`terminalSequence`**
(v2.1.141+; allowlisted OSC 0/1/2/9/99/777 and BEL — the supported way to ring a bell or
raise a desktop notification, since hooks have **no controlling terminal** as of
v2.1.139 and cannot write `/dev/tty`). Plus `decision`/`reason` and
`hookSpecificOutput` (requires `hookEventName`). **All hook output strings are capped at
10,000 characters** — over that, the content is spilled to a file and replaced with a
preview + path. Exit 0 → stdout parsed as JSON; exit 2 → stdout ignored, stderr fed back
as a blocking error. As of v2.1.214 exit 2 blocks even when the JSON fails validation.
Confidence: **high**.

**V43. `SessionStart` gained fields we should use: `sessionTitle`, `watchPaths`,
`reloadSkills`, `initialUserMessage`, and the `CLAUDE_ENV_FILE` env-persistence
channel.** `CLAUDE_ENV_FILE` is a path a SessionStart hook appends `export` lines to;
"Any variables written to this file will be available in **all subsequent Bash
commands**". Available on `SessionStart`, `Setup`, `CwdChanged`, `FileChanged` only.
Matcher values are `startup|resume|clear|compact|fork` (`fork` split out of `resume` in
v2.1.214). Only `command` and `mcp_tool` handler types are supported on SessionStart.
Confidence: **high**.

**V44. The disable key is `disableAllHooks`, not `disallowAllHooks`.** Verified against
`settings.md` line 256 and the JSON Schema. (A summarizing fetch of the same page
produced the wrong spelling — a good reminder that the raw `.md` is the source of truth.)
Confidence: **high**.

**V45. Matcher grammar has real gotchas.** A matcher containing only letters, digits,
`_`, `-`, space, `,`, `|` is an **exact string / alternation list**; anything else makes
it an **unanchored JavaScript regex**. So `Edit.*` also matches `NotebookEdit` — anchor
with `^Edit$`. Hyphens joined the exact-match set only in v2.1.195. `mcp__memory` alone
matches *nothing* (exact-match path); you must write `mcp__memory__.*`.
`FileChanged` and `StopFailure` use a narrower exact set (`|` only).
Confidence: **high**.

### G. New since mid-2026 worth baking in

**V46. Output styles still exist and are still `outputStyle` (string) + custom styles
with frontmatter — not deprecated, but wrong tool for us.** The doc itself routes us
away: "For instructions about your project, conventions, or codebase, use CLAUDE.md
instead." Requires restart (not hot-reloaded). Recommendation: **do not ship one**.
Confidence: **high**.

**V47. Memory has grown a real feature surface: auto-memory.** `autoMemoryEnabled`
(default `true`), `autoMemoryDirectory` (honors workspace trust from project/local
scope), `CLAUDE_CODE_DISABLE_AUTO_MEMORY`. v2.1.214 added an ISO `modified` timestamp to
memory-file frontmatter. AGENTS.md §11 already says "don't accumulate tribal knowledge in
auto-memory" — that instruction is still coherent, and `autoMemoryEnabled: false` is
available if we ever want to enforce rather than request it. Confidence: **high**.

**V48. No "statusline presets" feature exists.** The nearest thing is the `/statusline`
slash command, which asks Claude to *generate* the script for you
("`/statusline show model name and context percentage with a progress bar`").
Confidence: **high** (absence verified across statusline.md and the schema).

**V49. Plugin-packaging our repo-local pieces: technically possible, recommended
AGAINST for v1.** In favor: repo-declared plugins in `.claude/settings.json`
(`enabledPlugins` + `extraKnownMarketplaces`) **do install at cloud-session start**.
Against, decisively: (a) it requires network reachability to the marketplace source at
session start — a hard fail for an offline/air-gapped generated repo, whereas committed
`.claude/` files always work; (b) **plugin subagents silently ignore `hooks`,
`mcpServers`, and `permissionMode`** (V30), which would neuter our agent definitions;
(c) it adds a marketplace to maintain and version, for a template whose whole premise is
self-containment; (d) ADR-0008's sync model is built around net-new *files*, and
plugin-ifying would re-open C3/C4. Confidence: **high** on the mechanics, and this is a
judgment call on the recommendation.

**V50. Other genuinely new keys worth knowing (not proposed for v1):**
`workflowSizeGuideline` (v2.1.219), `skillOverrides` (v2.1.129, per-skill visibility;
`/skills` writes these to `settings.local.json`), `skillListingBudgetFraction` /
`skillListingMaxDescChars` (context budget for the skill listing — `/doctor` estimates
it), `footerLinksRegexes` (**user/managed only**, so unusable at project scope),
`attribution` (git commit/PR attribution), `prUrlTemplate`, `effortLevel`,
`disableBundledSkills`, `strictPluginOnlyCustomization` (managed-only lockdown that would
disable our entire `.claude/` surface — worth a one-line note in the template README so a
future enterprise deployment doesn't silently break the repo).
Confidence: **high**.

---

## Spec deltas

### SD-1 — contracts.md §9: add spinner + statusline toggles to the answers file

In the `ops:` block of the §9 YAML, after `signing: automatic`, insert:

```yaml
  spinner_flavor: true       # write spinnerVerbs + spinnerTipsOverride into .claude/settings.json
  statusline: false          # wire .claude/statusline.sh (shadows a personal statusLine — opt in)
```

Rationale: `spinner_flavor` defaults **true** (V4/V5 — project scope works everywhere,
costs nothing, `mode: append` is non-destructive). `statusline` defaults **false**
(V16 — `statusLine` is object-valued and would wholesale replace Pierce's personal
statusline in every generated repo). Both are new optional keys in
`template/answers.schema.json` with those defaults, so existing
`template/ci-combos/*.yaml` instances stay valid.

### SD-2 — contracts.md: new §11, the Claude-surfaces contract

Append to `contracts.md`:

> ## 11. Claude Code surface contract (ADR-0008; R5)
>
> Minimum supported Claude Code: **v2.1.144** (below this, custom `spinnerVerbs` leak
> into the past-tense turn-completion message). `.claude/settings.json` is Advisory
> under ADR-0008 and is the single place all wiring lives. Every script it references
> is a net-new Orphan file.
>
> **Committed `.claude/settings.json` skeleton (Apple additions marked):**
>
> ```json
> {
>   "$schema": "https://json.schemastore.org/claude-code-settings.json",
>   "spinnerVerbs": {
>     "mode": "append",
>     "verbs": ["Xcodegenerating", "Provisioning", "Codesigning", "..."]
>   },
>   "spinnerTipsOverride": {
>     "excludeDefault": false,
>     "tips": [
>       "Run `make verify` before declaring a slice done.",
>       "project.yml is the source of truth — never hand-edit MyApp.xcodeproj.",
>       "Extension bundle IDs are host ID + exactly one segment (ITMS-90347)."
>     ]
>   },
>   "hooks": {
>     "SessionStart": [
>       { "matcher": "startup|resume|clear|fork",
>         "hooks": [
>           { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start.sh",
>             "args": [], "timeout": 20 },
>           { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start-apple.sh",
>             "args": [], "timeout": 20, "statusMessage": "Checking Apple toolchain" }
>         ] }
>     ],
>     "UserPromptSubmit": [
>       { "hooks": [
>           { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/inject-state.sh",
>             "args": [], "timeout": 10 }
>         ] }
>     ],
>     "PreToolUse": [
>       { "matcher": "Bash",
>         "hooks": [
>           { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/bash-guard.sh",
>             "args": [] }
>         ] }
>     ],
>     "PostToolUse": [
>       { "matcher": "Edit|Write",
>         "hooks": [
>           { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/auto-lint.sh",
>             "args": [] }
>         ] },
>       { "matcher": "Edit|Write",
>         "if": "Edit(**/*.swift)",
>         "hooks": [
>           { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/auto-lint-swift.sh",
>             "args": [], "async": true, "asyncRewake": true, "timeout": 120,
>             "statusMessage": "Formatting Swift" }
>         ] }
>     ],
>     "PreCompact": [
>       { "hooks": [
>           { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/pre-compact.sh",
>             "args": [] }
>         ] }
>     ],
>     "Stop": [
>       { "hooks": [
>           { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/stop-gate.sh",
>             "args": [] }
>         ] }
>     ]
>   },
>   "permissions": {
>     "deny": [
>       "Bash(git push --force:*)",
>       "Read(./fastlane/.env*)",
>       "Read(**/AuthKey_*.p8)",
>       "Read(**/*.mobileprovision)",
>       "Read(**/*.p12)"
>     ]
>   }
> }
> ```
>
> Deltas vs. the skeleton baseline, each traceable to a verdict:
> - `serena-required.sh` (UserPromptSubmit) and `serena-gate.sh` (PreToolUse
>   `Read|Edit|MultiEdit|Write`) are **deleted** — ADR-0005.
> - Every handler moves to **exec form** (`args: []`), which removes the
>   `"\"$CLAUDE_PROJECT_DIR\"/..."` quoting hack (V40).
> - `PostToolUse` matcher drops `MultiEdit` (not a current tool name) and gains a
>   second, Swift-only group using `if: "Edit(**/*.swift)"` — note the `**/` prefix is
>   required as of v2.1.214 (V39).
> - The Swift lint hook is `async` + `asyncRewake` so `swiftformat`/`swiftlint` never
>   block a turn but still wake the session on failure (V38).
> - `SessionStart` matcher gains `fork` (v2.1.214 split it out of `resume`) (V43).
> - `permissions.deny` gains signing-material read denials (§7 Security hard stop:
>   "No secrets in source"); `permissions.*` arrays merge across scopes, so these add to
>   rather than replace Pierce's personal rules.

### SD-3 — contracts.md §11: the spinner corpus file and its wiring

Append to the new §11:

> **Spinner corpus.** `spinnerVerbs.verbs` accepts only an inline JSON array — Claude
> Code has no file-reference form (R5-V9). The corpus is therefore kept as a curated
> text file and *materialized* into `.claude/settings.json` by our own tooling:
>
> | Path | Role | Sync class (ADR-0008) |
> |---|---|---|
> | `.claude/spinner-verbs.txt` | source of truth; one gerund per line; `#` comments and blank lines ignored; ≥120 entries | Orphan (net-new) |
> | `.claude/spinner-tips.txt` | same format, one tip sentence per line | Orphan (net-new) |
> | `scripts/sync_spinner_verbs.py` | rewrites `spinnerVerbs.verbs` and `spinnerTipsOverride.tips` in `.claude/settings.json` in place; `--check` exits 1 on drift | Orphan (net-new; **name reserved** in the Phase-6 skill-update proposal) |
> | `make spinner-sync` / `make spinner-check` | 1:1 delegates | Advisory Makefile |
>
> `make spinner-check` joins the `make verify` gate chain so the committed
> `settings.json` can never drift from the corpus. The generator runs `spinner-sync`
> **after** token substitution, so verbs may legitimately contain `MyApp` and get
> renamed with everything else. Both `.txt` files and `.claude/settings.json` are plain
> text and MUST NOT be added to the generator's binary skip-list (contracts §1); the
> post-rename zero-residual-token lint applies to them normally.
>
> Corpus content rule: **gerunds only** (rendered as `<Verb>…`). No past-tense forms —
> since v2.1.144 the turn-completion message always uses built-in past-tense verbs
> (R5-V8). Keep entries ≤ ~16 characters so narrow terminals don't wrap.

### SD-4 — contracts.md §11: agent/command frontmatter correctness rules

Append to the new §11:

> **Subagent frontmatter (`.claude/agents/*.md`).** `tools:` takes **tool names only** —
> `Read`, `Grep`, `Glob`, `Bash`, plus `Agent(type,…)` and `mcp__<server>[__*]`.
> Permission-rule syntax such as `Bash(git diff:*)` does **not** resolve there and the
> tool is silently lost (R5-V26 — this is a live defect in the skeleton's shipped agents
> and in Pennywise). Narrow shell access with `permissions.allow` in `settings.json` or a
> per-hook `if:` filter, never inside `tools:`.
> `name` must not contain `:` (v2.1.218+ rejects the file). `model` accepts
> `sonnet|opus|haiku|fable|<full-id>|inherit`, defaulting to `inherit`.
>
> **Command/skill frontmatter.** `allowed-tools:` **does** take permission-rule syntax —
> the asymmetry with subagent `tools:` is deliberate and load-bearing. Emit `Agent`, not
> `Task` (renamed v2.1.63; `Task` survives only as an alias). Side-effectful commands
> (`/release`, `/onboard`) MUST set `disable-model-invocation: true` so Claude cannot
> trigger a release on its own initiative.
>
> **Skill directories.** For project skills the invoked command name comes from the
> **directory name**, not frontmatter `name` (R5-V21) — keep them identical.

### SD-5 — contracts.md §11: statusLine (opt-in)

Append to the new §11:

> **statusLine.** Wired only when `ops.statusline: true` (SD-1). Fragment:
>
> ```json
> {
>   "statusLine": {
>     "type": "command",
>     "command": "${CLAUDE_PROJECT_DIR}/.claude/statusline.sh",
>     "padding": 1,
>     "refreshInterval": 10
>   }
> }
> ```
>
> `type` must be the literal `"command"`; `additionalProperties` is `false`, so no other
> keys are accepted. The script reads one JSON object on stdin and prints one line per
> row. Budget: **< 300 ms** — Claude Code debounces at 300 ms and cancels an in-flight
> script when a new update arrives (R5-V14). Permitted: `jq`, `git rev-parse`,
> `git symbolic-ref`. Forbidden: `xcodebuild`, `xcodegen`, `swift`, `git status` on a
> large tree, anything on the network. Use `$COLUMNS`/`$LINES` for width — `tput cols`
> does not work inside the script. Suggested row 1:
> `model.display_name` · `workspace.repo.name` · branch · `worktree.name` when present;
> row 2: `context_window.used_percentage` bar · `cost.total_cost_usd` · `effort.level`.
> Note in the generated README that `disableAllHooks: true` disables the status line as
> well as hooks, and that a project `statusLine` replaces (does not merge with) a
> personal one.

### SD-6 — ADR-0008: amend the file inventory and add a version floor

In ADR-0008 § Decision, replace the file list sentence with:

> `hooks/session-start-apple.sh` (second SessionStart entry — C3),
> `hooks/auto-lint-swift.sh` (second PostToolUse entry, `if`-filtered to `**/*.swift`
> and run `async`+`asyncRewake` — C4), `rules/swift.md`,
> `commands/{onboard,release,grade-north-star}.md`,
> `agents/{apple-reviewer,xcode-build-debugger}.md`, `skills/release-ops/`,
> `spinner-verbs.txt`, `spinner-tips.txt`, `statusline.sh`, and
> `scripts/sync_spinner_verbs.py`.

And append to § Consequences:

> - Minimum Claude Code version for the generated repo is **v2.1.144**; the template
>   states this in its README and `session-start-apple.sh` warns (never blocks) below it.
> - The skeleton's own agent files carry a latent defect — permission-rule syntax in the
>   subagent `tools:` field, which does not resolve and silently strips `Bash`
>   (R5-V26). Our net-new agents avoid it; **fixing the skeleton's shipped agents is
>   added to the Phase-6 skill-update proposal**, alongside reserving the four new
>   filenames above.

### SD-7 — ADR-0005: no change required, one confirmation

No text change. R5 confirms the removal targets are exactly two `settings.json` entries
(`UserPromptSubmit` → `serena-required.sh`; `PreToolUse` matcher
`Read|Edit|MultiEdit|Write` → `serena-gate.sh`) plus the two scripts and
`rules/serena.md`. Because hook entries **merge across settings levels** rather than
replace (R5-V41), a generated repo cannot accidentally re-inherit them from the
skeleton's project settings — only from a user-level `~/.claude/settings.json`, which
this template does not write.

---

## Capability audit
*(DECISION-10 standing sub-task, ADR-0006: native capabilities our design under-uses,
and things we plan to hand-roll that the tooling already does.)*

### Things we planned to hand-roll that Claude Code already does natively

| # | Our plan | Native capability | Verdict |
|---|---|---|---|
| C1 | Filter the Swift lint hook by checking `${file##*.}` inside the shell script | Handler `if: "Edit(**/*.swift)"` (permission-rule syntax, tool events only) | **Adopt** — moves the branch out of bash into config. Mind the v2.1.214 `**/` change. |
| C2 | Background a slow `swiftformat` with `&`/`nohup` + a lockfile | `async: true` and `asyncRewake: true` on command hooks | **Adopt** — `asyncRewake` even wakes an idle session on exit 2. Deletes an entire category of hand-rolled process management. |
| C3 | Wrap hooks in `timeout 30 …` | Per-handler `timeout` (defaults 600/30/60 s, event-specific overrides) | **Adopt** |
| C4 | `"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/x.sh"` defensive quoting (baseline) | Exec form: `command` + `args: []`, no shell, no tokenization | **Adopt** |
| C5 | Print "running SwiftFormat…" from the hook to stdout | `statusMessage` on the handler — a *third* spinner surface, per-hook | **Adopt** — and it is on-theme with the headline ask. |
| C6 | Makefile targets each re-resolving `DEVELOPER_DIR`, mise/xcodegen `PATH` | `CLAUDE_ENV_FILE` in SessionStart: append `export` lines once, they apply to **every** subsequent Bash call | **Adopt** — the single highest-leverage under-used capability for an Apple repo. |
| C7 | A PostToolUse matcher watching for `project.yml` edits to remind about `xcodegen` | `FileChanged` event + `watchPaths` returned from SessionStart | **Adopt if cheap** — purpose-built; declarative watch list beats matcher heuristics. |
| C8 | Rely on the model remembering AGENTS.md §11 to update `TASK_STATE.md` at session end | `SessionEnd` hook (matchers `clear|resume|logout|prompt_input_exit|…`) | **Adopt with care** — the shared budget is **1.5 s** unless an explicit longer `timeout` raises it (cap 60 s). A cheap append is fine; a full state rewrite is not. |
| C9 | Nothing — xcodebuild failures just land in the transcript | `PostToolUseFailure` matched on `Bash` can inject "did you run `xcodegen`?" / "wrong simulator name?" hints exactly when a build fails | **Adopt** — free, targeted, zero context cost when builds pass. |
| C10 | Pushover for local long-build completion | Hook JSON `terminalSequence` (OSC 9/777 + BEL, allowlisted) — desktop notification/bell with no network and no secret | **Adopt for local**; keep Pushover for CI. |
| C11 | `rules/swift.md` loaded on every session | Skill frontmatter `paths: "**/*.swift"` gates automatic activation to Swift work | **Consider** — cuts always-on context. ADR-0008 already commits to `rules/swift.md`; treat `paths:` as the mechanism if it becomes a skill. |
| C12 | `/grade-north-star` running in the main conversation and flooding context | Skill `context: fork` + `agent:` (background by default since v2.1.218; `background: false` to wait) | **Adopt** — purpose-built for exactly this. |
| C13 | Permission prompts every time a skill runs its own bundled script | `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/x.sh *)` — the placeholder is substituted in `allowed-tools` too (v2.1.129+) | **Adopt** for `skills/release-ops/`. |
| C14 | A dirty main checkout after a failed build experiment | Subagent `isolation: worktree` — temp worktree off the default branch, auto-cleaned when unchanged | **Adopt for `xcode-build-debugger`** — one frontmatter line replaces a whole worktree dance. |
| C15 | Hoping `apple-reviewer` reads AGENTS.md | Subagent `skills:` preloads **full skill content** into the subagent at startup | **Adopt** |
| C16 | Hand-written statusline script | `/statusline "<description>"` generates it | **Use during W2E authoring**, then commit and review the result. |

### Native capabilities our current design simply doesn't use

- **`spinnerTipsOverride`** — a second, independent spinner surface. We were treating
  "spinner messages" as one thing. Adopted in SD-2.
- **`subagentStatusLine`** — per-subagent row formatting in the agent panel; carries
  model + effort as of v2.1.214. Not proposed for v1; noted for a later pass.
- **`skillOverrides`** (v2.1.129) — per-skill `on|name-only|user-invocable-only|off`.
  A generated repo could ship `disableBundledSkills`-style narrowing without editing any
  SKILL.md. Not v1.
- **`skillListingBudgetFraction` / `skillListingMaxDescChars`** — the skill listing has a
  context budget (default 1% of window, 1,536 chars/skill) and `/doctor` estimates it.
  Our long `when_to_use` blocks are silently truncated at 1,536 chars today. Worth a
  README line for skill authors.
- **`attribution`** — native git commit/PR attribution config; the skeleton's git
  discipline is currently prose-only.
- **`hooks` in skill/agent frontmatter** — component-scoped hooks with automatic cleanup,
  and `once: true` (honored in skill frontmatter only). A lighter alternative to
  settings-level wiring for anything that should exist only while a workflow runs.
- **`Notification` / `SubagentStart` / `SubagentStop` / `TaskCreated` / `TaskCompleted` /
  `ConfigChange` / `PostCompact`** — 25+ events we wire zero of. No v1 need identified,
  but the design should stop assuming five events is the whole surface.
- **`permissions.deny` for signing material** — the repo handles `.p8`, `.p12`, and
  `.mobileprovision`. §7 declares secrets a hard stop but nothing enforces it at the tool
  layer. Adopted in SD-2.

### Things a tool already does that we should explicitly NOT hand-roll

- **Do not build a plugin/marketplace to distribute our `.claude/` pieces.** Committed
  project files already load for all collaborators *and* in cloud sessions (V5, V18,
  V27), with no network dependency — and plugin subagents would silently drop `hooks`,
  `mcpServers`, and `permissionMode` (V30).
- **Do not write a user-settings installer for spinner verbs.** Project scope works
  (V4); an onboarding step that edits `~/.claude/settings.json` would be pure liability.
- **Do not write an output style.** The docs route project/convention instructions to
  CLAUDE.md, which we already own (V46).
- **Do not re-implement skill discovery or agent registration.** Both are filesystem
  watched with live reload (V18, V27).

---

## Sources

All fetched **2026-08-02**. Raw markdown (`.md` suffix) was used in preference to the
rendered pages; one summarizing fetch of the settings page produced a wrong key spelling
(`disallowAllHooks`) and omitted `spinnerVerbs` entirely, which the raw fetch corrected.

1. Claude Code settings reference — https://code.claude.com/docs/en/settings
   (raw: `https://code.claude.com/docs/en/settings.md`, 273,279 bytes). Spinner rows at
   lines 322–324; scopes and precedence at lines 11–120 and 657–724; hook configuration
   at 601–630; plugin settings at 758+.
2. Claude Code settings JSON Schema —
   https://www.schemastore.org/claude-code-settings.json (230,490 bytes, 143 top-level
   properties). Authoritative for `spinnerVerbs`, `spinnerTipsOverride`, `statusLine`,
   `subagentStatusLine` shapes and for the *absence* of any `maxItems` on `verbs`.
   (Note: `json.schemastore.org` returns a 301 to `www.schemastore.org`.)
3. Status line reference — https://code.claude.com/docs/en/statusline
   (raw `.md`, 62.7 KB). Schema, full stdin JSON, 300 ms debounce, ANSI/OSC 8/multi-line,
   `COLUMNS`/`LINES`, `subagentStatusLine`.
4. Hooks reference — https://code.claude.com/docs/en/hooks
   (raw `.md`, 245,465 bytes). ~30 events, five handler types, `timeout` defaults,
   `async`/`asyncRewake`, `if`, `statusMessage`, `once`, exec vs shell form, common
   input/JSON output, `terminalSequence`, 10,000-char cap, matcher grammar.
5. Subagents — https://code.claude.com/docs/en/sub-agents (raw `.md`, 95,655 bytes).
   Full frontmatter table, model aliases incl. `fable`, `isolation: worktree`,
   scope/precedence, `tools` semantics, plugin-subagent field restrictions, `--agents`.
6. Skills (now also the canonical slash-commands page) —
   https://code.claude.com/docs/en/skills (raw `.md`, 73,907 bytes). Frontmatter table,
   `where skills live`, command-name derivation, string substitutions,
   `` !`command` `` injection, `allowed-tools`/`disallowed-tools`, Cowork/cloud behavior.
   https://code.claude.com/docs/en/slash-commands.md returns the **byte-identical** body
   (73,907 bytes), confirming the merge.
7. Cloud environments — https://code.claude.com/docs/en/cloud-environments (raw `.md`).
   "What carries over from your setup" table.
8. Claude Code on the web — https://code.claude.com/docs/en/claude-code-on-the-web.
   "To change settings for a cloud session… commit settings files to the repository."
9. Output styles — https://code.claude.com/docs/en/output-styles (raw `.md`).
10. Claude Code CHANGELOG —
    https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
    (5,248 lines; head = **v2.1.220**). Version provenance: `spinnerVerbs` v2.1.23;
    `spinnerTipsOverride` v2.1.45; teammate-spinner fix v2.1.47; tips `excludeDefault`
    fix v2.1.122; turn-completion fixes v2.1.141 / v2.1.144; hook `if:` path-matching
    change v2.1.214; SessionStart `fork` source v2.1.214; subagent nesting v2.1.217 /
    v2.1.219; `DirectoryAdded` hook v2.1.219; skill `context: fork` background default
    and agent-name `:` rejection v2.1.218.
11. Deployed baseline (read-only): `/home/user/pennywise-apple-universal/.claude/settings.json`,
    `.claude/agents/reviewer.md`, `.claude/commands/review.md`.
12. Skeleton baseline (read-only):
    `/root/.claude/skills-src/agentic-skeleton/templates/greenfield/.claude/settings.json`.
13. Corroborating community reports on `spinnerVerbs` (used only to date the feature and
    cross-check `append`/`replace`, never as primary evidence):
    Daniel Miessler, "Customizing Your Claude Code Spinner Verbs"
    (https://danielmiessler.com/blog/customized-spinner-verbs-in-claude-code);
    Tristan Dunn, 2026-01-28 (https://tristandunn.com/2026/01/28/customizing-claude-code-spinner);
    lust.dev, 2026-01-28 (https://lust.dev/2026/01/28/claude-code-custom-spinner-verbs/).
