# R3 — MCP servers + 1Password secret injection

**Agent:** R3 · **Date:** 2026-08-02 · **Scope:** ADR-0005 item 2 (`.mcp.json`,
1Password injection, graceful degradation), contracts.md §10 deliverable format.
**Reference anti-pattern:** `/home/user/pennywise-apple-universal/.mcp.json` +
`.env.example`.

**Verification environment:** this remote container — Linux 6.18.5, Claude Code
**2.1.220**, node v22.22.2, npx 10.9.7, docker present, uvx present,
**`op` 2.34.0 present at `/usr/local/bin/op` and authenticated**. Every claim
below marked "**tested**" was executed here; every network probe hit the real
production endpoint. No secret value was ever printed — probes report HTTP
status, string length, or a redacted form only.

---

## Verdicts

### V1 — The brief's premise is wrong: `op` **is** present and authenticated in this container

**Claim.** The brief hypothesised "`op` absent (e.g. THIS remote container)".
It is not. `command -v op` → `/usr/local/bin/op`; `op --version` → `2.34.0`;
`op whoami` → `User Type: SERVICE_ACCOUNT`, `URL: https://my.1password.com`,
`Integration ID: E7QJ5RNAJVAWFJVZWYVITEI67Q`. `OP_SERVICE_ACCOUNT_TOKEN` is
exported into the session environment. `op vault list` returns exactly one
vault: **`agentic`** (`2cx47wjh6u2ke256ewlnx2fera`) — the service account is
already vault-scoped to `agentic`, which is the least-privilege posture
1Password recommends for `op run`.

**Evidence.** tested. Also: `GITHUB_TOKEN` is already exported in this
container's environment by the harness (value not inspected).

**Consequence.** The design must not assume "remote container ⇒ no op". The
real axis is **service-account (non-interactive, works headless)** vs
**desktop-app biometric (interactive, macOS/Windows only)**. Both Pierce's Macs
and this class of container can be op-enabled. The degradation path is still
required, but it is the *exception*, not the container default.

**Confidence: high** (directly observed).

---

### V2 — Secret-reference resolution: which `op` verb is the right wrapper

| Verb | What it does | Fit for `.mcp.json` |
|---|---|---|
| `op run [--env-file F] -- CMD` | resolves `op://` refs found in the **inherited environment** *and* in `--env-file` dotenvs, execs `CMD` with real values | **Works** as a stdio `command` wrapper — tested |
| `op read op://…` | prints one secret to stdout | **Best fit** for `headersHelper` (V4) and for `$(…)` capture in a wrapper script |
| `op inject -i tmpl -o out` | substitutes `op://` refs inside an arbitrary **file** | Wrong shape — MCP config is consumed by Claude Code, not by a templating step; writing a resolved `.mcp.json` to disk would put plaintext secrets in the working tree |
| `op item get` | structured item read | Overkill; `op read` is the documented one-secret primitive |

**Key tested facts about `op run`:**

1. **It resolves `op://` from the inherited environment, no `--env-file`
   needed.** `GITHUB_PERSONAL_ACCESS_TOKEN="op://agentic/scm-github/token" op
   run --no-masking -- sh -c 'echo ${#GITHUB_PERSONAL_ACCESS_TOKEN}'` → `93`.
   This matters because a `.mcp.json` `env:` block is merged into the spawned
   process environment, so `env` can hold **references** (not secrets) and
   `op run` resolves them at boot. That is ADR-0005-compliant: the committed
   file contains `op://agentic/scm-github/token`, which is a *pointer*, not a
   credential, and is not `${ENV}` expansion.
2. **`op run` is exec-safe for a non-shell spawn.** `.mcp.json` `command` is
   exec'd directly, not through a shell; `op run` is itself an executable that
   takes `-- cmd args…`, so no shell is required. Tested with a synthetic stdio
   JSON-RPC server driven over pipes.
3. **Masking does not break MCP stdio framing.** Default masking rewrites a
   leaked secret in the child's stdout to the literal `<concealed by
   1Password>` *inside the existing JSON string*, so the JSON stayed
   well-formed. Tested: a deliberate `{"secret":"<93-char token>"}` reply came
   back as `{"secret":"<concealed by 1Password>"}` and still parsed. Steady-state
   per-message latency: **~50 ms with masking, ~0 ms with `--no-masking`**
   (3-message round-trip, measured after the child signalled READY). No
   batching, no line-buffer stalls.
   → **Keep masking ON.** It is a free defence-in-depth: a misbehaving server
   cannot leak the token into the agent transcript. `--no-masking` is only for
   debugging.
4. **Cold-start cost is real: ~0.9–1.2 s per `op run` invocation** (3 runs:
   1165 ms / 986 ms / 1001 ms) versus 14 ms for `op --version`. That is a
   network round-trip to 1Password per spawned server. Budget for it in
   `MCP_TIMEOUT` if `op run` ever wraps a stdio server.
5. Flags in 2.34.0 are exactly: `--env-file stringArray`, `--no-masking`,
   `-h`. (`--environment`, for 1Password *Environments*, is documented but
   beta and needs ≥2.33.0-beta.02 — **do not use it in the template**.)

**Confidence: high** (all tested locally against the real service).

---

### V3 — Auth modes: service account vs biometric, for non-interactive spawns

| Mode | Trigger | Non-interactive spawn | Notes |
|---|---|---|---|
| **Service account** | `OP_SERVICE_ACCOUNT_TOKEN` env var | **Yes** — this container proves it | Vault-scopable (ours is scoped to `agentic` only). The correct mode for containers, CI, and any headless agent. |
| **Desktop app integration** (biometric) | 1Password 8 desktop app, "Integrate with 1Password CLI" toggle | **Yes, after first unlock** | Touch ID prompt may appear on first `op` call in a session; once the app is unlocked the CLI inherits the session without re-prompting. A spawned MCP server that hits a locked vault will *hang on a GUI prompt* until timeout — the wrapper's `timeout` guard (V5) is what prevents that becoming a stuck MCP boot. |
| **`op account add` + `op signin`** | manual password | **No** — needs a TTY, `OP_SESSION_*` expires (default 30 min) | Never rely on this in the template. |
| **Connect server** | `OP_CONNECT_HOST` + `OP_CONNECT_TOKEN` | Yes | Not used here; noted for completeness (Pierce's homelab could host one). |

The unauthenticated error is explicit and machine-detectable — tested by
running with `OP_SERVICE_ACCOUNT_TOKEN=""`:

```
No accounts configured for use with 1Password CLI.
 - Turn on the 1Password desktop app integration to sign in …
 - Add an account manually with 'op account add' …
 - Authenticate using a 1Password service account by setting the 'OP_SERVICE_ACCOUNT_TOKEN' …
 - Use 1Password CLI with a Connect server by setting 'OP_CONNECT_HOST' and 'OP_CONNECT_TOKEN' …
rc=1
```

`op read` on a missing item likewise exits 1 with
`could not resolve item UUID for item <x>: could not find item <x> in vault <id>`.
Both are non-zero exits on stderr — trivially trappable.

**Confidence: high** (tested for service-account and unauthenticated; biometric
behaviour is from 1Password's app-integration docs, not testable on Linux —
**med** for the biometric row).

---

### V4 — **`headersHelper` is the native Claude Code capability that solves this exactly.** We were about to hand-roll it.

**Claim.** Claude Code's `.mcp.json` supports a `headersHelper` field on
`http` / `sse` / `ws` servers: a command run **at each connection** whose stdout
JSON object is merged into the connection headers. This is purpose-built for
"short-lived tokens / internal SSO / an auth scheme that isn't OAuth" — i.e.
precisely the 1Password case.

**Evidence** (docs.claude.com → code.claude.com/docs/en/mcp, "Use dynamic
headers for custom authentication", fetched 2026-08-02):

> If your MCP server uses an authentication scheme other than OAuth, such as
> Kerberos, short-lived tokens, or an internal SSO, use `headersHelper` to
> generate request headers at connection time. Claude Code runs the command and
> merges its output into the connection headers.

> **Requirements:**
> * The command must write a JSON object of string key-value pairs to stdout
> * The command runs in a shell with a 10-second timeout, from the session's
>   current working directory. Use an absolute path or a command on `PATH` for
>   the script
> * Dynamic headers override any static `headers` with the same name

> The helper runs fresh on each connection, at session start and on reconnect.
> There is no caching, so your script is responsible for any token reuse.

> As of v2.1.193, if a tool call returns `401 Unauthorized` or `403 Forbidden`,
> Claude Code automatically re-runs the helper, reconnects with the fresh
> headers, and retries the call once.

Claude Code exports `CLAUDE_CODE_MCP_SERVER_NAME` and
`CLAUDE_CODE_MCP_SERVER_URL` to the helper, and the docs explicitly bless the
one-script-many-servers pattern: *"Use these to write a single helper script
that serves multiple MCP servers."*

**Why this beats every `op run` variant for our servers:** `op run` only helps a
**stdio** server. Our two credential-bearing servers (github, context7) are both
better run as **remote HTTP** (V6, V7), where there is no child process to wrap
— `headersHelper` is the only injection point, and it is a first-class one.

**Timing fits:** our helper measured **865–1159 ms**, comfortably inside the
10 s budget.

**Confidence: high** (docs quoted verbatim; helper behaviour tested locally end
to end against both live endpoints).

---

### V5 — Graceful degradation is *mostly native*; the wrapper only needs to emit `{}`

ADR-0005 says "the wrapper no-ops the optional server rather than breaking MCP
boot." Claude Code 2.1.220 already guarantees most of that:

1. **MCP startup is non-blocking.** *"MCP startup is otherwise non-blocking by
   default"* — only `alwaysLoad: true` blocks, and then only for the standard
   5-second connect timeout. A dead server cannot stall session start.
2. **A failed server is reported to the agent, by name, with its error.**
   *"When a configured server fails to connect, Claude Code tells Claude which
   server failed and its connection error, including in `ToolSearch` results
   that find no matching tool, so Claude reports the connection failure in its
   response."* (v2.1.205+; requires tool search, which is default-on.) That is
   literally the brief's "the agent sees a clear one-line reason", delivered by
   the harness.
3. **Needs-auth is a distinct, surfaced state.** *"Claude Code also shows a
   startup notice when one or more configured servers need authentication"*
   (v2.1.193+), and in non-interactive runs *"Claude Code tells Claude that the
   server's tools are unavailable until you authorize it"* (v2.1.196+).
4. **`claude mcp list` prints per-server health** — `✔ Connected`,
   `! Needs authentication`, `✘ Failed to connect`.

**What is still ours to build:** the helper must never *hard-fail*. The one
invariant is **always exit 0 and always print a JSON object**; printing `{}`
means "no credential", which sends **no `Authorization` header at all**, which
lets the server's own `WWW-Authenticate` drive Claude Code's OAuth discovery.

**The critical asymmetry — tested and documented:**

> If you configured `headers.Authorization` for the server and the server
> rejects that header, Claude Code reports the connection as **failed instead
> of falling back to OAuth**.

So a *static* `"headers": {"Authorization": "Bearer ${GITHUB_TOKEN}"}` with
`GITHUB_TOKEN` unset is the **worst** option: the docs confirm an unset variable
with no default *"uses the unexpanded `${VAR}` text as-is"*, so Claude Code
would send `Bearer ${GITHUB_TOKEN}` literally, get rejected, and mark the server
**failed with no OAuth fallback**. `headersHelper` → `{}` avoids this entirely.
This is the concrete technical reason ADR-0005's "no `${ENV}` secret expansion"
rule is correct, beyond the hygiene argument.

**Wrapper script — final text (destination `scripts/mcp/op-headers.sh`):**

```sh
#!/usr/bin/env sh
# Emit MCP connection headers as a JSON object on stdout (Claude Code `headersHelper`).
#
# CONTRACT: always exit 0, always print one JSON object.
# Printing `{}` means "no credential available" — Claude Code then sends no
# Authorization header, the remote server answers 401 + WWW-Authenticate, and
# Claude Code falls back to its own OAuth flow (`/mcp` or `claude mcp login`).
# Any non-JSON output or hard failure here would break the server instead of
# degrading it.
set -u

VAULT="${MCP_OP_VAULT:-agentic}"

say()       { printf '%s\n' "op-headers: $*" >&2; }   # one-line reason, stderr only
emit_none() { printf '{}\n'; exit 0; }

case "${CLAUDE_CODE_MCP_SERVER_NAME:-}" in
  github)   ref="op://${VAULT}/scm-github/token" ;;
  context7) ref="op://${VAULT}/svc-context7/password" ;;
  *)        say "no secret mapping for server '${CLAUDE_CODE_MCP_SERVER_NAME:-?}'; sending no auth header"
            emit_none ;;
esac

if ! command -v op >/dev/null 2>&1; then
  say "1Password CLI (op) not on PATH; '${CLAUDE_CODE_MCP_SERVER_NAME}' falls back to OAuth/keyless"
  emit_none
fi

# 8s budget: Claude Code kills headersHelper at 10s.
if ! token=$(timeout 8 op read --no-newline "$ref" 2>/dev/null) || [ -z "$token" ]; then
  say "op could not resolve ${ref} (not signed in, no vault access, or offline); falling back to OAuth/keyless"
  emit_none
fi

printf '{"Authorization":"Bearer %s"}\n' "$token"
```

**Degradation matrix — all six paths tested here:**

| Path | stdout | stderr | exit | valid JSON |
|---|---|---|---|---|
| A. github, op authed | `{"Authorization":"Bearer …"}` | — | 0 | yes |
| B. context7, op authed | `{"Authorization":"Bearer …"}` | — | 0 | yes |
| C. `op` absent from PATH | `{}` | `op-headers: 1Password CLI (op) not on PATH; 'github' falls back to OAuth/keyless` | 0 | yes |
| D. `op` present, unauthenticated | `{}` | `op-headers: op could not resolve op://agentic/scm-github/token (not signed in, no vault access, or offline); falling back to OAuth/keyless` | 0 | yes |
| E. unknown server name | `{}` | `op-headers: no secret mapping for server 'sentry'; sending no auth header` | 0 | yes |
| F. `CLAUDE_CODE_MCP_SERVER_NAME` unset | `{}` | `…server '?'…` | 0 | yes |

**End-to-end, against the live endpoints:**
- Path A output → `POST https://api.githubcopilot.com/mcp/` → **HTTP 200**,
  full `initialize` result (`serverInfo.name = "github-mcp-server"`,
  `protocolVersion = "2025-06-18"`).
- Path C/D output (`{}`, i.e. no header) → **HTTP 401** with
  `www-authenticate: Bearer error="invalid_request", …
  resource_metadata="https://api.githubcopilot.com/.well-known/oauth-protected-resource/mcp/"`
  — exactly the discovery header Claude Code needs
  (*"A custom server that returns a `WWW-Authenticate` header pointing to its
  authorization server gets the same automatic discovery as any other remote
  server."*).
- Path B output → `POST https://mcp.context7.com/mcp` → **HTTP 200**.

**Path resolution — do not use a bare relative path.** `headersHelper` runs
"from the session's current working directory", and `${CLAUDE_PROJECT_DIR}` is
**not** in the documented expansion list for `.mcp.json`
(`command`, `args`, `env`, `url`, `headers` only). Tested: `./scripts/mcp/…`
fails with `not found` when `claude` is launched from a subdirectory. The
git-root-resolving one-liner is robust and was tested from repo root, from
`sub/deep/`, and with the script deleted:

```
f="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/scripts/mcp/op-headers.sh"; [ -r "$f" ] && exec sh "$f"; echo "{}"
```

(script deleted → prints `{}`, exit 0; non-executable → still works, because it
is invoked as `sh "$f"` rather than executed directly.)

**Confidence: high** (every row tested; docs quoted).

---

### V6 — GitHub MCP: the **hosted remote endpoint is the answer**, and it is op-free *and* op-friendly

Three options, all current as of 2026-08-02:

| Option | Endpoint / image | Auth | Verdict |
|---|---|---|---|
| **Hosted remote** | `https://api.githubcopilot.com/mcp/` (`type: "http"`) | OAuth (Dynamic Client Registration, discovered from `WWW-Authenticate`) **or** `Authorization: Bearer <PAT>` | **Recommended.** No Docker, no image pulls, no local process, auto-updating. |
| **Docker** | `ghcr.io/github/github-mcp-server` | Now supports **browser OAuth** (`-p 127.0.0.1:8085:8085 -e GITHUB_OAUTH_CALLBACK_PORT`, token in memory only) as well as `GITHUB_PERSONAL_ACCESS_TOKEN` | Only for air-gapped / policy-restricted hosts. Costs a container per session. |
| **Native binary** | `go build ./cmd/github-mcp-server`, run `stdio` | PAT env var or the same OAuth flow | Only if you want no Docker *and* no network dependency on the hosted plane. |

GitHub's own docs call the remote server *"the easiest method for getting up and
running"* and recommend it when the host supports remote servers. Claude Code
does (v2.1.1+), and GitHub ships a Claude-Code-specific install guide whose
primary form is `claude mcp add-json github '{"type":"http","url":"https://api.githubcopilot.com/mcp","headers":{"Authorization":"Bearer YOUR_GITHUB_PAT"}}'`.

**Tested against production:**
- unauthenticated → 401 + `WWW-Authenticate` + `resource_metadata` (OAuth
  discovery works)
- `Authorization: Bearer $(op read op://agentic/scm-github/token)` → **200**,
  `initialize` returns 44 tools

**Recommendation: hosted endpoint + `headersHelper`.** This single config is
correct on *both* surfaces without branching:
- **Pierce's Macs** — if the desktop-app integration is on, `op read` succeeds
  and the PAT is used; if not, the helper emits `{}` and Claude Code offers
  OAuth via `/mcp` or `claude mcp login github` (v2.1.186+). Either way it
  works, interactively.
- **Remote containers** — the service account resolves the PAT headlessly
  (proven here). If a future container has no `op`, the server lands in
  `! Needs authentication` and the agent is *told so by name*, which is the
  documented non-interactive behaviour and is strictly better than a silently
  missing server.

**Do not** use the local Docker option in the template: it adds a hard Docker
dependency to every generated repo for zero capability gain.

**Confidence: high** (docs + live probes).

---

### V7 — context7: keyless works today; the **remote endpoint** beats `npx`; key is an optional upgrade

- **Package is current, not deprecated.** `@upstash/context7-mcp` — npm
  `version = 3.2.5`, `time.modified = 2026-07-25T03:38:37.508Z`, no `deprecated`
  field. (Pennywise pins nothing and runs `npx -y`, so it silently jumped 1.x → 3.x.)
- **Remote endpoint `https://mcp.context7.com/mcp` works with no credential
  at all.** Tested from this container: `initialize` → **HTTP 200**,
  `serverInfo = {"name":"Context7","version":"3.2.5"}`; `tools/list` → **HTTP
  200** returning `resolve-library-id` and `query-docs`.
  **Note the tool rename:** the old `get-library-docs` is now **`query-docs`** —
  any prompt/doc text in the template that names `get-library-docs` is stale.
- **Rate limits are deliberately undocumented as numbers.** The official API
  guide says only *"Without API key: Low rate limits and no custom
  configuration. With API key: Higher limits based on your plan."* On 429 the
  API returns `Retry-After`, `RateLimit-Limit`, `RateLimit-Remaining`,
  `RateLimit-Reset`. Upstash's own Claude Code page states: *"If the variable is
  not set, the plugin still works — requests just go through the anonymous tier,
  which has lower rate limits."* **No published req/min figure exists** — do not
  invent one in template docs.
- **Key injection.** `Authorization: Bearer <ctx7sk_…>` is the documented form;
  the endpoint's CORS `Access-Control-Allow-Headers` also advertises
  `X-Context7-API-Key`, `Context7-API-Key`, `X-API-Key`. Pierce already has one:
  `op://agentic/svc-context7/password` (43 chars, `ctx7sk` prefix — matches the
  documented key format). Tested with that key → **HTTP 200**.
- **`--api-key` as an argv flag is the wrong shape anyway.** Pennywise passes
  `"--api-key", "${CONTEXT7_API_KEY}"` in `args`, which puts the credential on
  the **process command line**, visible to `ps` for every user on the machine.
  That is the sharpest edge of the anti-pattern we are replacing, sharper than
  the `.env` file itself.
- A bad key does not break the handshake (tested: bogus `ctx7sk_…` → still
  HTTP 200 on `initialize`), so a stale key degrades to anonymous-tier behaviour
  rather than a failed server. Safe.

**Recommendation: remote HTTP + the same `headersHelper`.** No `npx` spawn, no
node dependency, no per-session package download, key optional.

**Confidence: high** for behaviour and package currency; **med** for the exact
anonymous-tier limit (genuinely unpublished).

---

### V8 — sequential-thinking: same package name, current, zero config

- `@modelcontextprotocol/server-sequential-thinking` — npm `version =
  2026.7.4`, `time.modified = 2026-07-04`, repo
  `github.com/modelcontextprotocol/servers`, **no `deprecated` field**. The
  package name in Pennywise's `.mcp.json` is still correct.
- **Boot tested here:** `npx -y @modelcontextprotocol/server-sequential-thinking`
  → stderr `Sequential Thinking MCP Server running on stdio`;
  `initialize` → `{"name":"sequential-thinking-server","version":"0.2.0"}`,
  protocol `2025-06-18`; `tools/list` → exactly one tool, **`sequentialthinking`**.
- No API key, no env, no config. One tool → negligible context cost.
- Note the date-based npm version (`2026.7.4`) vs the internal server version
  (`0.2.0`) — don't confuse them when writing docs.

**Confidence: high** (tested).

---

### V9 — Final `.mcp.json` for the template

Three servers, **zero secrets**, **zero `${ENV}` expansion**, **zero Serena**
(ADR-0005 item 1), one wrapper script.

```json
{
  "$schema": "https://modelcontextprotocol.io/schema/v1/mcp.json",
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headersHelper": "f=\"$(git rev-parse --show-toplevel 2>/dev/null || pwd)/scripts/mcp/op-headers.sh\"; [ -r \"$f\" ] && exec sh \"$f\"; echo \"{}\""
    },
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headersHelper": "f=\"$(git rev-parse --show-toplevel 2>/dev/null || pwd)/scripts/mcp/op-headers.sh\"; [ -r \"$f\" ] && exec sh \"$f\"; echo \"{}\""
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    }
  }
}
```

Plus `scripts/mcp/op-headers.sh` (V5, mode 0755).

**Design notes.**
- `"type"` is mandatory on both HTTP entries: *"A JSON entry that has a `url` but
  no `type` is a configuration error, because Claude Code reads an entry with no
  `type` as a stdio server."* (`streamable-http` is an accepted alias.)
- No `env` blocks, no `${…}` anywhere. The only file-resident strings are a URL,
  a package name, and a shell command — nothing a secret scanner can flag and
  nothing a leaked repo would expose.
- No `MCP_TIMEOUT` env pinning is needed: the Serena 60 s timeout that Pennywise
  carried existed only because Serena's first LSP init is slow. With Serena gone
  and both credentialed servers remote, boot is fast.
- `alwaysLoad` is deliberately **not** set: it forces upfront tool loading *and*
  blocks startup for up to 5 s per server. Tool search (default-on) is the
  better default.

**Same file on both surfaces.** There is no Mac-vs-container variant — that is
the point of the design. What differs is only *how the credential arrives*:

| | Pierce's Macs | Remote container (this one) | Container with no `op` |
|---|---|---|---|
| `op` auth mode | desktop-app biometric (or a service-account token in the shell profile) | `OP_SERVICE_ACCOUNT_TOKEN`, vault-scoped to `agentic` | n/a |
| github | PAT via helper; if `op` is locked/absent → `{}` → OAuth via `/mcp` or `claude mcp login github` | PAT via helper (**proven, HTTP 200**) | `{}` → `! Needs authentication`, agent told by name |
| context7 | keyed if `op` available, else anonymous tier — **works either way** | keyed (**proven**) | anonymous tier, still works |
| sequential-thinking | works | works | works |

**Confidence: high** for the config; **med** for one sub-claim — that a
`headersHelper` returning `{}` leaves OAuth discovery intact (the docs state the
no-fallback rule for *static* `headers.Authorization` specifically, and `{}`
provably sends no such header, but I could not exercise Claude Code's internal
fallback branch from here). If it turns out otherwise, the fallback is to drop
`headersHelper` from `github` and rely on pure OAuth + `claude mcp login`, which
costs only the headless-container case.

---

### V10 — Operational gotcha the template MUST document: cloned repos can't self-approve

> As of v2.1.196, `claude mcp list` and `claude mcp get` read `.mcp.json`
> approvals only from settings files that aren't checked into the repository
> until you trust the workspace by running `claude` in it and accepting the
> workspace trust dialog. **A cloned repository can't approve its own servers:**
> `enableAllProjectMcpServers` or `enabledMcpjsonServers` committed to the
> project's `.claude/settings.json` is ignored in an untrusted folder, and the
> server stays at `⏸ Pending approval`.

Consequence for a **template** whose whole output is freshly-cloned repos: do
**not** ship `enableAllProjectMcpServers: true` in `.claude/settings.json` and
expect it to work — it is inert until the trust dialog is accepted. And the
`headersHelper` note reinforces it: *"`headersHelper` executes arbitrary shell
commands. When defined at project or local scope, it only runs after you accept
the workspace trust dialog."* First-run onboarding must say: *run `claude` once
interactively in the new repo, accept workspace trust, approve the three MCP
servers.*

**Confidence: high** (docs quoted).

---

### V11 — 1Password developer-docs domain has moved

`https://developer.1password.com/docs/cli/...` now **301**s to
`https://www.1password.dev/cli/...`. Any URL the template or skill docs cite
should use the new host. (`op`'s own CLI help text still prints the old
`developer.1password.com` URLs, so it will keep leaking the stale domain into
error messages — cosmetic only.)

**Confidence: high** (observed redirect).

---

## Spec deltas

### D1 — ADR-0005, Decision item 2: rewrite to match reality

**Current text:**

> 2. **MCP secrets come from 1Password at boot or the server is omitted.**
>    The GitHub MCP server ships only if its token injects via 1Password CLI
>    (`op run` / `op read` against Pierce's `agentic` vault) at server-boot time;
>    context7 ships with no API-key argument (keyless mode) unless op-injected.
>    No `${ENV_VAR}` secret expansion for tokens in the committed `.mcp.json`.
>    Graceful degradation when `op` is absent (remote containers): the wrapper
>    no-ops the optional server rather than breaking MCP boot. Exact wrapper
>    mechanics per research R3.

**Replace with:**

> 2. **MCP secrets come from 1Password at connect time via `headersHelper`, and
>    every server degrades to a working credential-free mode.**
>    `github` and `context7` are configured as **remote HTTP** servers
>    (`https://api.githubcopilot.com/mcp/`, `https://mcp.context7.com/mcp`).
>    Both use one `headersHelper` script, `scripts/mcp/op-headers.sh`, which
>    resolves a PAT/API key with `op read` against Pierce's `agentic` vault.
>    The script's contract is **always exit 0, always print one JSON object**;
>    it prints `{}` when `op` is missing, locked, or offline, having written a
>    one-line reason to stderr. `{}` sends no `Authorization` header, so github
>    falls through to Claude Code's own OAuth flow (`/mcp`,
>    `claude mcp login github`) and context7 falls through to its anonymous
>    tier — both remain usable. No `${ENV_VAR}` expansion for tokens, and no
>    credential ever appears in `args` (a command line is world-readable via
>    `ps`). `sequential-thinking` is stdio and needs no credential.
>    Servers are **never omitted**; a credential-less server degrades in place,
>    and Claude Code reports its state to the agent by name. Wrapper text and
>    the verified degradation matrix: `specs/_build/research/R3-mcp.md` §V5.

### D2 — ADR-0005, Context: correct the container premise

**Current text:**

> Graceful degradation when `op` is absent (remote containers)

**Replace the parenthetical wherever it appears with:**

> Graceful degradation when `op` is absent, locked, or lacks vault access

**Rationale:** verified false as stated — this remote container has `op` 2.34.0
authenticated as a service account scoped to `agentic`. The real distinction is
service-account (headless-capable) vs desktop-biometric (interactive) auth, not
Mac vs container.

### D3 — ADR-0005, Consequences: replace the second bullet

**Current text:**

> - Sessions without 1Password lose the GitHub MCP server (GitHub access then
>   flows through the platform's own integration, e.g. remote-session MCP).

**Replace with:**

> - Sessions without 1Password do **not** lose the GitHub MCP server: it stays
>   configured and Claude Code surfaces it as `! Needs authentication`, offering
>   OAuth sign-in via `/mcp` or `claude mcp login github`. In a non-interactive
>   run Claude Code names the server as needing authorization rather than acting
>   as if it were unconfigured. Only the *credential source* changes.
> - `headersHelper` and project-scoped `.mcp.json` approvals both require the
>   workspace trust dialog, which a committed `enableAllProjectMcpServers`
>   cannot pre-satisfy in a freshly cloned repo. Generated-repo onboarding must
>   include one interactive `claude` run to accept trust and approve servers.

### D4 — contracts.md: add §11 (new section, MCP surface is currently unspecified)

`contracts.md` has no MCP section, so implementation waves have nothing frozen
to code against. Add:

> ## 11. MCP surface (ADR-0005)
>
> `.mcp.json` ships exactly three servers and zero secrets:
> `github` (`type: http`, `https://api.githubcopilot.com/mcp/`),
> `context7` (`type: http`, `https://mcp.context7.com/mcp`), and
> `sequential-thinking` (stdio, `npx -y @modelcontextprotocol/server-sequential-thinking`).
> The two HTTP servers share one `headersHelper`, `scripts/mcp/op-headers.sh`,
> invoked through the git-root-resolving shell one-liner in
> `specs/_build/research/R3-mcp.md` §V9. The script maps
> `CLAUDE_CODE_MCP_SERVER_NAME` → `op://${MCP_OP_VAULT:-agentic}/…` and MUST
> always exit 0 printing a JSON object (`{}` = no credential). No Serena server,
> hook, rule, flag, or workflow step exists anywhere. `.env` / `.env.example`
> carry **no** MCP credentials — the file is not the secret channel.

### D5 — `.gitignore` / secret-scanner note for the generator

The template's `.env.example` must **not** reproduce Pennywise's
`CONTEXT7_API_KEY=` / `GITHUB_TOKEN=` block. Those keys no longer participate in
MCP boot, and leaving them documented invites someone to fill them in. If
`.env.example` mentions MCP at all, it should say:

```
# MCP servers take no credentials from this file.
# github + context7 resolve theirs at connect time from 1Password
# (scripts/mcp/op-headers.sh) and degrade to OAuth / anonymous tier without it.
```

### D6 — Any doc text naming context7's tools

`get-library-docs` is gone; the current tools are **`resolve-library-id`** and
**`query-docs`** (verified live, server v3.2.5). Grep generated docs/prompts for
`get-library-docs` before tagging.

---

## Capability audit

*Decision-10 / ADR-0006 standing sub-task: native capabilities of the tools in
this domain that our design under-uses, and things we planned to hand-roll that
a tool already does.*

### Things we were about to hand-roll that already exist

1. **`headersHelper` — the whole 1Password injection mechanism.** ADR-0005
   scoped a bespoke "wrapper that no-ops the optional server". Claude Code
   already ships a first-class, per-connection, per-server header generator with
   a documented 10 s budget, documented env contract
   (`CLAUDE_CODE_MCP_SERVER_NAME`, `CLAUDE_CODE_MCP_SERVER_URL`), automatic
   re-run + retry on 401/403, and an explicit blessing of the
   one-script-many-servers pattern. Our "wrapper" collapses to ~25 lines whose
   only job is `op read` + `{}`. **Biggest single under-use found.**
2. **Fail-soft MCP boot.** We planned to engineer "doesn't break the whole MCP
   boot". MCP startup is already non-blocking by default; only `alwaysLoad: true`
   blocks, and then for ≤5 s.
3. **"The agent sees a clear one-line reason."** Claude Code already tells the
   model which server failed and why (v2.1.205+), surfaces a needs-auth startup
   notice (v2.1.193+), and names unauthorized servers in non-interactive runs
   (v2.1.196+). Our stderr line is a *debugging* nicety for `claude mcp list`
   runs, not the primary channel. Do not build a status-reporting MCP server.
4. **OAuth as the no-op fallback.** We assumed "no token ⇒ omit the server."
   Both remote servers have a real credential-free mode (GitHub: full OAuth with
   DCR, advertised via `WWW-Authenticate` + `resource_metadata`; context7:
   anonymous tier). Omission was never necessary.
5. **`claude mcp login <name>`** (v2.1.186+) authenticates a configured server
   from the shell without opening `/mcp`. Worth a line in the onboarding
   Makefile/doc instead of "run `/mcp` and click".
6. **`op run` resolving refs from the inherited environment.** We assumed
   `--env-file` was required, which would have meant committing a dotenv of
   `op://` refs. It is not: an `env` block of references is enough. (Not needed
   for our three servers, but this is the correct recipe for any *stdio* server
   that ever does need a secret — record it rather than rediscover it.)
7. **`op read --no-newline`** exists; no `tr -d '\n'` / `printf` gymnastics.
   Also `--out-file` + `--file-mode` (default `0600`) if a secret must ever land
   on disk (e.g. the App Store Connect `.p8` — coordinate with R1's
   `APP_STORE_CONNECT_API_KEY_P8_PATH` finding rather than each inventing a
   mechanism).

### Native capabilities we are choosing not to use, and why

8. **Remote GitHub MCP toolset scoping via URL path.** Verified live tool
   counts: `/mcp/` = **44**, `/mcp/readonly` = **27**, `/mcp/x/repos` = **13**,
   `/mcp/x/repos/issues` = **19**, `/mcp/x/pull_requests` = **10**. Segments are
   slash-separated (`/x/a/b`); **comma-separated lists silently yield 0 tools**
   (`/x/repos,issues,pull_requests` → 0) and an unknown toolset yields 0
   (`/x/bogus_toolset` → 0) — a silent-empty failure mode worth knowing.
   Not used by default because tool search already defers definitions, but
   `https://api.githubcopilot.com/mcp/readonly` is a **cheap, real safety lever**
   for a template that hands repos to autonomous agents, and deserves a
   commented line in `.mcp.json`. Recommend documenting, defaulting to full.
9. **Per-server `timeout`** (ms, per tool call) and
   `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`. Not needed at our scale; noted so nobody
   reaches for a hook to enforce a timeout.
10. **`alwaysLoad`** (v2.1.121+) — deliberately unused, see V9.
11. **Per-subagent `mcpServers:` scoping** (the skeleton already documents this
    for heavy MCPs). With only three light servers plus default tool search, the
    template does not need it.
12. **`op` service-account vault scoping.** Already correct here (the token sees
    only `agentic`), so the blast radius of an MCP server reading a secret is
    one vault. Worth stating explicitly in the template's security notes as an
    intentional control rather than an accident.
13. **1Password *Environments* (`op run --environment`)** — would let Pierce keep
    the ref→var mapping server-side instead of in the script. Beta, needs
    ≥2.33.0-beta.02. **Do not adopt in v1**; revisit when GA.

### Anti-patterns confirmed in the reference repo (feed into the Pennywise security note, Phase 6)

14. **Secret on the command line.** `"args": ["-y","@upstash/context7-mcp","--api-key","${CONTEXT7_API_KEY}"]` exposes the key to `ps` for every local
    user. Worse than the `.env` file it came from.
15. **`.env` as the credential channel** for MCP, contradicting
    `.claude/rules/security.md` ("Environment variables are the only source of
    truth for credentials" is satisfied in letter but the file *is* the store).
    Replaced wholesale.
16. **Unpinned `npx -y` / `uvx --from git+…`** against a moving target: Pennywise
    silently rode `@upstash/context7-mcp` 1.x → 3.2.5, including the
    `get-library-docs` → `query-docs` tool rename. Our design removes both npx
    context7 and uvx Serena; only `sequential-thinking` remains unpinned, and it
    exposes exactly one tool.
17. **Docker dependency for GitHub MCP** where an HTTP URL does the same job.
18. **Stale skeleton guidance.** `agentic-skeleton/references/mcp-servers.md`
    still says *"Environment variable placeholders are mandatory"*, prescribes
    the Docker+`${GITHUB_TOKEN}` github entry, calls Serena *"the single
    highest-leverage MCP install"*, and prices the canonical four at
    *"~8–12K tokens/session … a permanent tax"*. All four statements are now
    wrong for this template: ADR-0005 bans the placeholders and Serena, and tool
    search (default-on since it defers MCP tool definitions) removes the
    per-session tax. Flag for the Phase-6 skill-update proposal.

---

## Sources

Fetched or executed 2026-08-02.

**Official documentation**
- Claude Code — Connect Claude Code to tools via MCP: https://code.claude.com/docs/en/mcp
  (`docs.claude.com/en/docs/claude-code/mcp` 301s here). Sections used:
  transport `type` requirement, environment-variable expansion in `.mcp.json`,
  "Use dynamic headers for custom authentication" (`headersHelper`),
  "Authenticate with remote MCP servers", "Scale with MCP tool search",
  `alwaysLoad`, `claude mcp list` health states, workspace-trust/approval rules.
- 1Password — Load secrets into the environment (`op run`):
  https://www.1password.dev/cli/secrets-environment-variables/
  (`developer.1password.com/docs/cli/secrets-environment-variables/` 301s here).
- 1Password — Service accounts: https://developer.1password.com/docs/service-accounts/
  (referenced by `op`'s own error output; redirects to `www.1password.dev`).
- GitHub — `github/github-mcp-server` README: https://github.com/github/github-mcp-server
  (remote endpoint, Docker OAuth callback, toolsets, `--read-only`).
- GitHub — Claude install guide: https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md
- GitHub Docs — Setting up the GitHub MCP Server: https://docs.github.com/en/copilot/how-tos/provide-context/use-mcp-in-your-ide/set-up-the-github-mcp-server
- Context7 — API guide (rate-limit language, `Authorization: Bearer`, 429
  headers): https://context7.com/docs/api-guide.md
- Context7 — Claude Code client page (anonymous tier statement,
  `CONTEXT7_API_KEY`): https://context7.com/docs/clients/claude-code.md
- Context7 — repo README: https://github.com/upstash/context7
- npm — `@upstash/context7-mcp` 3.2.5 (modified 2026-07-25);
  `@modelcontextprotocol/server-sequential-thinking` 2026.7.4 (modified
  2026-07-04) — queried via `npm view` against registry.npmjs.org.

**Local execution (this container, 2026-08-02)**
- `command -v op` → `/usr/local/bin/op`; `op --version` → `2.34.0`;
  `op whoami` → SERVICE_ACCOUNT; `op vault list` → single vault `agentic`.
- `op run --help` (flag list, masking statement, subshell caveat);
  `op read --help` (`--no-newline`, `--out-file`, `--file-mode 0600`).
- `op run` inherited-env reference resolution; masking vs `--no-masking`
  JSON-RPC round-trip over pipes; cold-start timing (986–1165 ms);
  unauthenticated and bad-ref failure output.
- `scripts/mcp/op-headers.sh` degradation matrix, 6 paths (V5 table);
  timing 865–1159 ms; git-root path resolution from repo root, from a deep
  subdirectory, with the script deleted, and non-executable.
- Live MCP `initialize` / `tools/list` probes:
  `https://api.githubcopilot.com/mcp/` (401 unauth + `WWW-Authenticate`
  `resource_metadata`; 200 with op-sourced PAT; 44 tools) and its
  `/readonly` (27), `/x/repos` (13), `/x/repos/issues` (19),
  `/x/pull_requests` (10), `/x/repos,issues,pull_requests` (0),
  `/x/bogus_toolset` (0) variants;
  `https://mcp.context7.com/mcp` (200 keyless, 200 with op-sourced key,
  200 with a bogus key; tools `resolve-library-id`, `query-docs`;
  `serverInfo.version` 3.2.5).
- `npx -y @modelcontextprotocol/server-sequential-thinking` stdio boot →
  `sequential-thinking-server` 0.2.0, protocol 2025-06-18, one tool
  `sequentialthinking`.
- `claude --version` → 2.1.220 (above every version floor cited above).

**Repository sources (read-only)**
- `/home/user/pennywise-apple-universal/.mcp.json`, `.env.example` (anti-pattern).
- `/root/.claude/skills-src/agentic-skeleton/references/mcp-servers.md` (stale
  guidance, item 18).
- `/home/user/template-apple-swift/docs/adr/0005-no-serena-mcp-secrets.md`,
  `0009-walking-skeleton-and-gates.md`,
  `/home/user/template-apple-swift/specs/_build/contracts.md`.
