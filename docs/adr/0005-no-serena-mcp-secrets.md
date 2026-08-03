# ADR 0005 — No Serena anywhere; MCP secrets via 1Password or omission

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner)
- **Scope:** `.mcp.json`, `.claude/` hooks/rules, AGENTS.md workflow — template
  and every generated repo

## Context

Pennywise's retrofit wired Serena deeply: `.mcp.json` server entry,
`serena-required.sh` (hard prompt gate), `serena-gate.sh` (blocks native
Read/Edit on Swift), `rules/serena.md`, gitignore flags, AGENTS.md workflow
steps. Pierce wants Serena disabled everywhere and eventually removed from the
skeleton (a separate effort). Separately, Pennywise's `.mcp.json` expands
secrets from env (`${GITHUB_TOKEN}`, `${CONTEXT7_API_KEY}`) with `.env` as the
documented source — credentials sitting in a dotfile.

## Decision

1. **Zero Serena.** No serena server, hooks, rules, flags, or workflow steps
   anywhere in this template or its generated output. The skeleton's
   serena-related files are simply not copied; `/sync-skills` runs must not
   reintroduce them (documented in the template's sync notes).
2. **MCP secrets come from 1Password at connect time via `headersHelper`, and
   every server degrades to a working credential-free mode.**
   `github` and `context7` are configured as **remote HTTP** servers
   (`https://api.githubcopilot.com/mcp/`, `https://mcp.context7.com/mcp`).
   Both use one `headersHelper` script, `scripts/mcp/op-headers.sh`, which
   resolves a PAT/API key with `op read` against Pierce's `agentic` vault.
   The script's contract is **always exit 0, always print one JSON object**;
   it prints `{}` when `op` is missing, locked, or offline, having written a
   one-line reason to stderr. `{}` sends no `Authorization` header, so github
   falls through to Claude Code's own OAuth flow (`/mcp`,
   `claude mcp login github`) and context7 falls through to its anonymous
   tier — both remain usable. No `${ENV_VAR}` expansion for tokens, and no
   credential ever appears in `args` (a command line is world-readable via
   `ps`). `sequential-thinking` is stdio and needs no credential.
   Servers are **never omitted**; a credential-less server degrades in place,
   and Claude Code reports its state to the agent by name. Wrapper text and
   the verified degradation matrix: construction research `R3-mcp.md` §V5
   (`specs/_build/`, deleted at end of construction — see git history).
   Graceful degradation applies when `op` is absent, locked, or lacks vault
   access — the real distinction is service-account (headless-capable) vs
   desktop-biometric (interactive) auth, not Mac vs container (R3 verified
   this remote container HAS an authed `op` service account scoped to
   `agentic`).

## Consequences

- Agents in generated repos use built-in tools; no symbolic-edit gate exists.
- Sessions without 1Password do **not** lose the GitHub MCP server: it stays
  configured and Claude Code surfaces it as `! Needs authentication`, offering
  OAuth sign-in via `/mcp` or `claude mcp login github`. In a non-interactive
  run Claude Code names the server as needing authorization rather than acting
  as if it were unconfigured. Only the *credential source* changes.
- `headersHelper` and project-scoped `.mcp.json` approvals both require the
  workspace trust dialog, which a committed `enableAllProjectMcpServers`
  cannot pre-satisfy in a freshly cloned repo. Generated-repo onboarding must
  include one interactive `claude` run to accept trust and approve servers.
- The skeleton-wide Serena removal remains Pierce's separate effort; this repo
  is the Serena-free reference implementation.
