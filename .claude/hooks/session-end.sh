#!/usr/bin/env bash
# Stop hook — distill the just-ended session and upsert SessionContext.
# NON-BLOCKING: failures log to stderr and exit 0 so session shutdown is never
# blocked. If shanebrain_distill_session isn't built yet, this is a no-op.
#
# Env overrides:
#   SHANEBRAIN_MCP_URL  default: http://localhost:8100

set -u

SESSION_ID="$(cat /tmp/shanebrain/claude-session-id 2>/dev/null || echo "unknown-$(date +%s)")"
SURFACE="claude_code"
MCP_URL="${SHANEBRAIN_MCP_URL:-http://localhost:8100}"

curl -fsS --max-time 3 \
  -X POST "${MCP_URL}/tools/shanebrain_distill_session" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"${SESSION_ID}\",\"surface\":\"${SURFACE}\"}" \
  >/dev/null 2>&1 \
  || echo "<!-- shanebrain_distill_session unavailable; session not distilled to SessionContext. shanebrain_log_conversation may still have captured the transcript. -->" >&2

exit 0
