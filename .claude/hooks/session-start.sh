#!/usr/bin/env bash
# SessionStart hook — ShaneBrain continuity layer (Phase 1).
#
# TRANSPORT RATIONALE: shanebrain-mcp uses StreamableHTTP at /mcp (JSON-RPC
# envelopes). Plain REST POSTs to /tools/* return 404. Pi hooks call Weaviate
# v1 REST directly. The MCP tools (shanebrain_session_start_context) still
# exist for Phase 2 surfaces (claude.ai, API) that reach them via Gateway.
#
# MULTI-NODE: this hook works from any Tailscale-bound node. The default
# WEAVIATE URL resolves to localhost on `shanebrain` (Pi) and to the Tailscale
# hostname `shanebrain` from any other node (neworleans, gulfshores, jaxton…).
# Each node gets its own continuity thread via surface = "claude_code:<host>".
#
# NON-BLOCKING: any failure emits an HTML comment and exits 0.
# Env overrides:
#   SHANEBRAIN_WEAVIATE_URL  default: localhost on shanebrain, http://shanebrain:8080 elsewhere
#   CLAUDE_SESSION_ID        default: uuidgen / nanosecond timestamp

set -u

# Source canonical service locations. One file, one source of truth.
INFRA_FILE="$(dirname "$0")/../infra.env"
[ -f "$INFRA_FILE" ] && . "$INFRA_FILE"

NODE="$(hostname 2>/dev/null || echo unknown)"
SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen 2>/dev/null || date +%s%N)}"
SURFACE="claude_code:${NODE}"

WEAVIATE_HOST="${SHANEBRAIN_WEAVIATE_HOST:-shanebrain}"
WEAVIATE_PORT="${SHANEBRAIN_WEAVIATE_PORT:-8080}"

# If running ON the Weaviate host, prefer localhost (skip the DNS hop)
if [ "$NODE" = "$WEAVIATE_HOST" ]; then
  WEAVIATE_DEFAULT="http://localhost:${WEAVIATE_PORT}"
else
  WEAVIATE_DEFAULT="http://${WEAVIATE_HOST}:${WEAVIATE_PORT}"
fi
WEAVIATE="${SHANEBRAIN_WEAVIATE_URL:-$WEAVIATE_DEFAULT}"

mkdir -p /tmp/shanebrain 2>/dev/null || true
echo "$SESSION_ID" > /tmp/shanebrain/claude-session-id 2>/dev/null || true

# Fetch last SessionContext for this surface via Weaviate v1 GraphQL
RESP=$(curl -fsS --max-time 3 \
  -X POST "${WEAVIATE}/v1/graphql" \
  -H 'Content-Type: application/json' \
  -d "{\"query\":\"{Get{SessionContext(where:{path:[\\\"surface\\\"],operator:Equal,valueText:\\\"${SURFACE}\\\"},sort:[{path:[\\\"started_at\\\"],order:desc}],limit:1){session_id surface summary in_flight last_touched_paths open_decisions ended_at}}}\"}" \
  2>/dev/null) || RESP=""

if [ -z "$RESP" ]; then
  echo "<!-- ShaneBrain SessionContext unavailable. WEAVIATE=${WEAVIATE}. Proceeding without distilled state; CLAUDE.md still loaded. -->"
  exit 0
fi

# Write response to temp file to avoid shell expansion issues
echo "$RESP" > /tmp/shanebrain/sc_resp.json 2>/dev/null || true

# Format to markdown
python3 - "$SESSION_ID" "$SURFACE" <<'PY'
import sys, json

try:
    with open('/tmp/shanebrain/sc_resp.json') as f:
        data = json.load(f)
    session_id = sys.argv[1]
except Exception as e:
    print(f"<!-- ShaneBrain SessionContext: parse error ({e}). -->")
    sys.exit(0)

rows = (data.get("data") or {}).get("Get", {}).get("SessionContext") or []
surface = sys.argv[2] if len(sys.argv) > 2 else "claude_code"
lines = [f"# SessionContext — surface={surface}", ""]

if rows:
    r = rows[0]
    lines.append(f"## Last session ({r.get('ended_at') or 'in-flight'})")
    lines.append(r.get("summary") or "(no summary)")
    if r.get("in_flight"):
        lines.append("\n### In-flight")
        lines += [f"- {x}" for x in r["in_flight"]]
    if r.get("last_touched_paths"):
        lines.append("\n### Last touched")
        lines += [f"- `{x}`" for x in r["last_touched_paths"]]
    if r.get("open_decisions"):
        lines.append("\n### Open decisions")
        lines += [f"- {x}" for x in r["open_decisions"]]
else:
    lines.append("_No prior SessionContext for this surface._")

lines.append("")
lines.append(f"_session_id: {session_id}_")
print("\n".join(lines))
PY

exit 0
