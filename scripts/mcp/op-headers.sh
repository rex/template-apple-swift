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
