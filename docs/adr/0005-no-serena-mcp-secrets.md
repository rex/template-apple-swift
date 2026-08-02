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
2. **MCP secrets come from 1Password at boot or the server is omitted.**
   The GitHub MCP server ships only if its token injects via 1Password CLI
   (`op run` / `op read` against Pierce's `agentic` vault) at server-boot time;
   context7 ships with no API-key argument (keyless mode) unless op-injected.
   No `${ENV_VAR}` secret expansion for tokens in the committed `.mcp.json`.
   Graceful degradation when `op` is absent (remote containers): the wrapper
   no-ops the optional server rather than breaking MCP boot. Exact wrapper
   mechanics per research R3.

## Consequences

- Agents in generated repos use built-in tools; no symbolic-edit gate exists.
- Sessions without 1Password lose the GitHub MCP server (GitHub access then
  flows through the platform's own integration, e.g. remote-session MCP).
- The skeleton-wide Serena removal remains Pierce's separate effort; this repo
  is the Serena-free reference implementation.
