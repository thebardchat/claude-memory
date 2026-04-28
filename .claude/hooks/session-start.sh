#!/usr/bin/env bash
# SessionStart hook — ShaneBrain continuity layer (Phase 1).
# Pulls a markdown digest from shanebrain-mcp and emits it as additionalContext.
# NON-BLOCKING: any failure prints an HTML comment and exits 0 so a cold session
# can still proceed. The hook never breaks the session.
#
# Env overrides:
#   SHANEBRAIN_MCP_URL  default: http://localhost:8100
#   CLAUDE_SESSION_ID   default: uuidgen / nanosecond timestamp

set -u

SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen 2>/dev/null || date +%s%N)}"
SURFACE="claude_code"
MCP_URL="${SHANEBRAIN_MCP_URL:-http://localhost:8100}"

# Persist session id so the Stop hook can reference the same row
mkdir -p /tmp/shanebrain 2>/dev/null || true
echo "$SESSION_ID" > /tmp/shanebrain/claude-session-id 2>/dev/null || true

# Try the new continuity tool first
RESP=$(curl -fsS --max-time 3 \
  -X POST "${MCP_URL}/tools/shanebrain_session_start_context" \
  -H 'Content-Type: application/json' \
  -d "{\"surface\":\"${SURFACE}\",\"session_id\":\"${SESSION_ID}\"}" 2>/dev/null) || RESP=""

# Fall back to the existing context_snapshot tool if the new one isn't built yet
if [ -z "$RESP" ]; then
  RESP=$(curl -fsS --max-time 3 \
    -X POST "${MCP_URL}/tools/context_snapshot" \
    -H 'Content-Type: application/json' \
    -d '{}' 2>/dev/null) || RESP=""
fi

if [ -n "$RESP" ]; then
  echo "$RESP"
else
  echo "<!-- ShaneBrain SessionContext unavailable. MCP_URL=${MCP_URL}. Proceeding without distilled state; CLAUDE.md still loaded. -->"
fi

exit 0
